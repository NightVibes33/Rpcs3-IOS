#!/usr/bin/env python3
from __future__ import annotations

import argparse
import shutil
from pathlib import Path


def copy_file(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)


def wire_full_build(repo: Path) -> list[Path]:
    changed: list[Path] = []
    invocation = 'python3 scripts/patch-upstream-apple-mobile-platform.py "$ROOT"\n'
    for path in sorted((repo / "scripts").glob("*.sh")):
        text = path.read_text(encoding="utf-8")
        if "patch-upstream-ios-full-qt-blockers.py" not in text or "patch-upstream-apple-mobile-platform.py" in text:
            continue
        lines = text.splitlines(keepends=True)
        for index, line in enumerate(lines):
            if "patch-upstream-ios-full-qt-blockers.py" in line:
                indent = line[: len(line) - len(line.lstrip())]
                lines.insert(index + 1, indent + invocation)
                break
        path.write_text("".join(lines), encoding="utf-8")
        changed.append(path)
    return changed


def wire_standard_cmake(repo: Path) -> Path | None:
    path = repo / "CMakeLists.txt"
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8")
    marker = "RPCS3 Apple mobile standard Qt target integration"
    if marker in text:
        return None
    block = r'''

if(CMAKE_SYSTEM_NAME STREQUAL "iOS" AND TARGET RPCS3QtIOS)
    # RPCS3 Apple mobile standard Qt target integration.
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
        set(RPCS3_IOS_PORT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")
    endif()
    include("${RPCS3_IOS_PORT_ROOT}/cmake/RPCS3AppleMobile.cmake")
    rpcs3_enable_apple_mobile(RPCS3QtIOS)
endif()
'''
    path.write_text(text.rstrip() + block, encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_root", type=Path)
    parser.add_argument("--bundle-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    bundle = args.bundle_root.resolve()
    if not (repo / ".git").exists() and not (repo / "CMakeLists.txt").exists():
        raise SystemExit(f"Not an Rpcs3-IOS checkout: {repo}")

    relative_files = [
        "CoreBridge/RPCS3AppleMobilePlatform.h",
        "CoreBridge/RPCS3AppleMobilePlatform.mm",
        "cmake/RPCS3AppleMobile.cmake",
        "scripts/patch-upstream-apple-mobile-platform.py",
        "scripts/audit-apple-mobile-port.py",
    ]
    for relative in relative_files:
        copy_file(bundle / relative, repo / relative)

    changed = wire_full_build(repo)
    standard = wire_standard_cmake(repo)
    if standard:
        changed.append(standard)

    print("Installed the shared iOS/iPadOS port files")
    for path in changed:
        print(f"Wired: {path.relative_to(repo)}")
    if not changed:
        print("No build script anchor was changed; call patch-upstream-apple-mobile-platform.py after the existing full-Qt blocker patch.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
