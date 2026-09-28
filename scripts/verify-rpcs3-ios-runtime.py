#!/usr/bin/env python3
"""
RPCS3-iOS build/runtime evidence verifier.

This intentionally separates:
  1. static build wiring,
  2. IPA packaging,
  3. PKG installation,
  4. guest boot,
  5. Vulkan/MoltenVK initialization,
  6. actual rendering/presentation.

It exits non-zero until every requested layer has evidence.
"""

from __future__ import annotations

import argparse
import json
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path
from typing import Any


REQUIRED_COMPILED_SOURCES = {
    "unpkg.cpp": "RPCS3 PKG decryption/extraction",
    "pkg_install_dialog.cpp": "upstream Qt PKG installer",
    "System.cpp": "guest boot/runtime core",
    "main_window.cpp": "upstream RPCS3 main window",
    "gui_application.cpp": "upstream RPCS3 Qt application",
    "VulkanAPI.cpp": "Vulkan API loader/device logic",
    "VKGSRender.cpp": "RPCS3 Vulkan RSX renderer",
    "VKPresent.cpp": "Vulkan presentation path",
    "swapchain.cpp": "Vulkan swapchain path",
}

REQUIRED_LINK_ITEMS = {
    "librpcs3_lib.a": "RPCS3 application/core library",
    "librpcs3_ui.a": "upstream Qt frontend library",
    "librpcs3_emu.a": "emulation core",
    "libMoltenVK.a": "Vulkan-to-Metal implementation",
    "libSPIRV.a": "SPIR-V tooling",
    "libglslang.a": "shader compiler",
    "-framework Metal": "Metal",
    "-framework QuartzCore": "CAMetalLayer host",
    "-framework UIKit": "iOS application/window host",
}

FATAL_PATTERNS = [
    r"\bfatal error:",
    r"\bBUILD FAILED\b",
    r"\bundefined symbols?\b",
    r"\bclang: error:",
    r"\bld: error:",
    r"\bVK_ERROR_DEVICE_LOST\b",
    r"\bVulkan API call failed\b",
    r"\bclass std::(?:runtime_error|logic_error) thrown\b",
    r"\bAccess violation\b",
]

PKG_INSTALL_SUCCESS_PATTERNS = [
    r"successfully installed",
    r"package.+installed",
    r"installed package",
    r"PKG.+100(?:\.0+)?%",
]

BOOT_PATH_PATTERN = re.compile(
    r"(?:SYS|LDR):\s+Path:\s+.*?/dev_hdd0/game/([A-Z0-9]{9})/USRDIR/EBOOT\.BIN",
    re.IGNORECASE,
)

VULKAN_DEVICE_PATTERNS = [
    r"Found Vulkan-compatible GPU",
    r"Vulkan-compatible GPU",
    r"MoltenVK",
]

# RPCS3 revisions vary in how much present/swapchain detail they log. At least
# one explicit renderer/presentation marker must be supplied by the app or log.
PRESENT_PATTERNS = [
    r"swapchain.+created",
    r"created.+swapchain",
    r"first frame.+present",
    r"presented frame",
    r"vkQueuePresentKHR",
    r"RPCS3_IOS_FIRST_FRAME_PRESENTED",
]


def run_command(argv: list[str]) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            argv,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        return proc.returncode, proc.stdout
    except FileNotFoundError:
        return 127, f"{argv[0]} not installed"


def result(name: str, ok: bool, detail: str, *, required: bool = True) -> dict[str, Any]:
    return {
        "name": name,
        "ok": bool(ok),
        "required": bool(required),
        "detail": detail,
    }


def inspect_static_evidence(root: Path) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    build_log = root / "full-rpcs3-qt-ios-build/logs/build-full-rpcs3.log"
    project = root / "full-rpcs3-qt-ios-build/tree/rpcs3.xcodeproj/project.pbxproj"
    graph_log = root / "full-rpcs3-qt-ios-build/logs/full-qt-graph.log"

    if not build_log.is_file() or not project.is_file():
        return [
            result(
                "Static evidence present",
                False,
                f"Expected build log/project under {root}",
            )
        ]

    build_text = build_log.read_text(encoding="utf-8", errors="replace")
    project_text = project.read_text(encoding="utf-8", errors="replace")
    graph_text = graph_log.read_text(encoding="utf-8", errors="replace") if graph_log.is_file() else ""

    checks.append(
        result(
            "Real upstream app target",
            'productType = "com.apple.product-type.application";' in project_text
            and "name = rpcs3;" in project_text
            and 'PRODUCT_NAME = "RPCS3-iOS";' in project_text,
            "Xcode graph contains the upstream rpcs3 application target named RPCS3-iOS.",
        )
    )

    for source, purpose in REQUIRED_COMPILED_SOURCES.items():
        ok = bool(re.search(rf"CompileC .*?/{re.escape(Path(source).stem)}\.o .*?/{re.escape(source)}\b", build_text))
        checks.append(result(f"Compiled {source}", ok, purpose))

    for item, purpose in REQUIRED_LINK_ITEMS.items():
        checks.append(result(f"Linked {item}", item in project_text, purpose))

    checks.extend(
        [
            result(
                "Writable iOS VFS overlay",
                "Made RPCS3_CONFIG_DIR authoritative for the shared iOS dev_hdd0/dev_flash tree" in graph_text,
                "The iOS config root owns dev_hdd0/dev_flash instead of using a desktop executable directory.",
            ),
            result(
                "CAMetalLayer Vulkan WSI overlay",
                "Apple Vulkan WSI helper to consume the iOS CAMetalLayer handle" in graph_text,
                "The Vulkan surface path is redirected to the iOS layer host.",
            ),
        ]
    )

    fatal_lines = []
    for lineno, line in enumerate(build_text.splitlines(), 1):
        if any(re.search(pattern, line, re.IGNORECASE) for pattern in FATAL_PATTERNS):
            fatal_lines.append(f"{lineno}: {line.strip()}")
    checks.append(
        result(
            "Build completed without compiler/linker failure",
            not fatal_lines,
            "No fatal compiler/linker errors found."
            if not fatal_lines
            else "Fatal build evidence: " + " | ".join(fatal_lines[-8:]),
        )
    )
    return checks


def find_app(payload_root: Path) -> Path | None:
    apps = sorted((payload_root / "Payload").glob("*.app"))
    return apps[0] if len(apps) == 1 else None


def inspect_ipa(ipa: Path) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    if not ipa.is_file():
        return [result("IPA exists", False, str(ipa))]

    with tempfile.TemporaryDirectory(prefix="rpcs3-ios-ipa-") as td:
        root = Path(td)
        try:
            with zipfile.ZipFile(ipa) as zf:
                zf.extractall(root)
        except (zipfile.BadZipFile, OSError) as exc:
            return [result("IPA is a valid ZIP", False, str(exc))]

        app = find_app(root)
        checks.append(result("Single app bundle in IPA", app is not None, str(app) if app else "Expected Payload/*.app"))
        if app is None:
            return checks

        info_path = app / "Info.plist"
        info: dict[str, Any] = {}
        if info_path.is_file():
            try:
                info = plistlib.loads(info_path.read_bytes())
            except Exception as exc:
                checks.append(result("Readable Info.plist", False, str(exc)))
        else:
            checks.append(result("Readable Info.plist", False, f"Missing {info_path}"))

        bundle_id = str(info.get("CFBundleIdentifier", ""))
        executable_name = str(info.get("CFBundleExecutable", ""))
        executable = app / executable_name if executable_name else None

        checks.extend(
            [
                result(
                    "Expected bundle identifier",
                    bundle_id == "com.nightvibes33.rpcs3ios",
                    bundle_id or "missing",
                ),
                result(
                    "App executable present",
                    executable is not None and executable.is_file(),
                    str(executable) if executable else "CFBundleExecutable missing",
                ),
            ]
        )

        if executable and executable.is_file():
            rc, output = run_command(["file", str(executable)])
            checks.append(result("arm64 device Mach-O", rc == 0 and "arm64" in output and "Mach-O" in output, output.strip()))

            strings_tool = shutil.which("strings")
            if strings_tool:
                rc, strings = run_command([strings_tool, str(executable)])
                checks.append(
                    result(
                        "Packaged Vulkan renderer evidence",
                        rc == 0 and any(token in strings for token in ("VKGSRender", "MoltenVK", "Vulkan")),
                        "Renderer-related binary strings present." if rc == 0 else strings.strip(),
                    )
                )
            else:
                checks.append(result("Packaged Vulkan renderer evidence", False, "strings tool unavailable"))

    return checks


def inspect_install_tree(root: Path, title_id: str | None) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    game_root = root / "dev_hdd0/game"
    checks.append(result("dev_hdd0 game directory exists", game_root.is_dir(), str(game_root)))
    if not game_root.is_dir():
        return checks

    candidates = []
    if title_id:
        candidates = [game_root / title_id.upper()]
    else:
        candidates = sorted(p for p in game_root.iterdir() if p.is_dir() and re.fullmatch(r"[A-Z0-9]{9}", p.name))

    valid = []
    for candidate in candidates:
        eboot = candidate / "USRDIR/EBOOT.BIN"
        param = candidate / "PARAM.SFO"
        if eboot.is_file():
            valid.append(
                {
                    "title_id": candidate.name,
                    "eboot": str(eboot),
                    "param_sfo": str(param) if param.is_file() else None,
                }
            )

    checks.append(
        result(
            "Installed bootable PKG title",
            bool(valid),
            json.dumps(valid, indent=2) if valid else "No TITLEID/USRDIR/EBOOT.BIN found.",
        )
    )
    return checks


def inspect_runtime_log(log_path: Path, title_id: str | None) -> list[dict[str, Any]]:
    checks: list[dict[str, Any]] = []
    if not log_path.is_file():
        return [result("Runtime log exists", False, str(log_path))]

    text = log_path.read_text(encoding="utf-8", errors="replace")
    fatal_hits = [
        line.strip()
        for line in text.splitlines()
        if any(re.search(pattern, line, re.IGNORECASE) for pattern in FATAL_PATTERNS)
    ]

    installed = any(re.search(pattern, text, re.IGNORECASE | re.DOTALL) for pattern in PKG_INSTALL_SUCCESS_PATTERNS)
    boot_match = BOOT_PATH_PATTERN.search(text)
    boot_id = boot_match.group(1).upper() if boot_match else None
    expected_id_ok = not title_id or boot_id == title_id.upper()

    checks.extend(
        [
            result(
                "PKG installer reported success",
                installed,
                "Install success marker found." if installed else "No package-install success marker found.",
            ),
            result(
                "Booted installed EBOOT.BIN",
                boot_match is not None and expected_id_ok,
                f"title_id={boot_id}" if boot_id else "No /dev_hdd0/game/TITLEID/USRDIR/EBOOT.BIN boot path found.",
            ),
            result(
                "VFS mounted writable dev_hdd0",
                bool(re.search(r'VFS: Mounted path "/dev_hdd0"', text, re.IGNORECASE)),
                "RPCS3 mounted /dev_hdd0.",
            ),
            result(
                "Vulkan/MoltenVK GPU initialized",
                any(re.search(pattern, text, re.IGNORECASE) for pattern in VULKAN_DEVICE_PATTERNS),
                "GPU/driver initialization marker found.",
            ),
            result(
                "First frame presented",
                any(re.search(pattern, text, re.IGNORECASE) for pattern in PRESENT_PATTERNS),
                "A swapchain/present marker is mandatory; compilation alone is not accepted.",
            ),
            result(
                "No runtime fatal error",
                not fatal_hits,
                "No fatal runtime markers found." if not fatal_hits else " | ".join(fatal_hits[-8:]),
            ),
        ]
    )
    return checks


def write_markdown(report: dict[str, Any], output: Path) -> None:
    lines = ["# RPCS3-iOS verification report", ""]
    lines.append(f"**Overall: {'PASS' if report['ok'] else 'FAIL'}**")
    lines.append("")
    for section in report["sections"]:
        lines.append(f"## {section['name']}")
        lines.append("")
        for check in section["checks"]:
            icon = "✅" if check["ok"] else ("❌" if check["required"] else "⚠️")
            lines.append(f"- {icon} **{check['name']}** — {check['detail']}")
        lines.append("")
    output.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--ipa", type=Path)
    parser.add_argument("--runtime-log", type=Path)
    parser.add_argument("--installed-root", type=Path)
    parser.add_argument("--title-id")
    parser.add_argument("--json-output", type=Path)
    parser.add_argument("--markdown-output", type=Path)
    args = parser.parse_args()

    sections: list[dict[str, Any]] = []
    if args.evidence_root:
        sections.append({"name": "Static build wiring", "checks": inspect_static_evidence(args.evidence_root)})
    if args.ipa:
        sections.append({"name": "IPA packaging", "checks": inspect_ipa(args.ipa)})
    if args.installed_root:
        sections.append(
            {
                "name": "Installed PKG filesystem",
                "checks": inspect_install_tree(args.installed_root, args.title_id),
            }
        )
    if args.runtime_log:
        sections.append(
            {
                "name": "On-device runtime",
                "checks": inspect_runtime_log(args.runtime_log, args.title_id),
            }
        )

    if not sections:
        parser.error("Provide at least one evidence input.")

    required_checks = [
        check for section in sections for check in section["checks"] if check.get("required", True)
    ]
    report = {
        "ok": bool(required_checks) and all(check["ok"] for check in required_checks),
        "sections": sections,
    }

    print(json.dumps(report, indent=2))
    if args.json_output:
        args.json_output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if args.markdown_output:
        write_markdown(report, args.markdown_output)

    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
