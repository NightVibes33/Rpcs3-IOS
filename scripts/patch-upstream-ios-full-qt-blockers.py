#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
from pathlib import Path


APPLE_HID_MARKER = "RPCS3 Apple mobile pthread barrier compatibility"
RUNTIME_HID_MARKER = "RPCS3 iOS: pthread barriers are unavailable on iPhoneOS"


def verify_python(script: Path) -> None:
    raw = script.read_bytes()
    try:
        raw.decode("utf-8")
    except UnicodeDecodeError as error:
        raise SystemExit(f"Patch script is not valid UTF-8: {script}: {error}") from error
    subprocess.run([sys.executable, "-m", "py_compile", str(script)], check=True)


def patch_apple_mobile_source(port_root: Path) -> None:
    source = port_root / "CoreBridge/RPCS3AppleMobilePlatform.mm"
    text = source.read_text(encoding="utf-8")

    # Objective-C declarations must be at global scope. Close the anonymous
    # namespace after the C++ controller helper, then reopen it after @end so
    # the remaining internal helpers retain internal linkage.
    bad_boundary = "    return buttons;\n}\n\n@interface RPCS3AppleMobileControllerPump"
    good_boundary = "    return buttons;\n}\n} // namespace\n\n@interface RPCS3AppleMobileControllerPump"
    if bad_boundary in text:
        text = text.replace(bad_boundary, good_boundary, 1)

    bad_reopen = "@end\n\nvoid set_idle_timer(bool display_sleep_enabled)"
    good_reopen = "@end\n\nnamespace\n{\nvoid set_idle_timer(bool display_sleep_enabled)"
    if bad_reopen in text:
        text = text.replace(bad_reopen, good_reopen, 1)

    replacements = {
        "(long)state": "static_cast<long>(state)",
        "(int)screen.maximumFramesPerSecond": "static_cast<int>(screen.maximumFramesPerSecond)",
        "(int)info.activeProcessorCount": "static_cast<int>(info.activeProcessorCount)",
    }
    for old, new in replacements.items():
        text = text.replace(old, new)

    if good_boundary not in text:
        raise SystemExit("Apple-mobile controller Objective-C declaration is still inside the C++ namespace")
    if good_reopen not in text:
        raise SystemExit("Apple-mobile internal helper namespace was not reopened after @implementation")
    for forbidden in replacements:
        if forbidden in text:
            raise SystemExit(f"Apple-mobile source still contains a fatal old-style cast: {forbidden}")

    source.write_text(text, encoding="utf-8")
    print("Patched Apple-mobile Objective-C++ namespace and cast blockers")


def run_patch(script: Path, upstream_root: str) -> None:
    verify_python(script)
    subprocess.run([sys.executable, str(script), upstream_root], check=True)


def run_apple_mobile_patch(script: Path, upstream_root: str) -> None:
    """Run the Apple-mobile patch without adding a second HIDAPI barrier fallback."""

    verify_python(script)
    header = Path(upstream_root) / "3rdparty/hidapi/hidapi/libusb/hidapi_thread_pthread.h"
    text = header.read_text(encoding="utf-8")
    if RUNTIME_HID_MARKER not in text:
        raise SystemExit("The runtime blocker did not install HIDAPI's single iPhoneOS barrier fallback")
    if APPLE_HID_MARKER in text:
        raise SystemExit("The upstream HIDAPI header already contains the duplicate Apple-mobile fallback marker")

    sentinel = f"/* {APPLE_HID_MARKER}: suppressed because the runtime blocker owns this fallback. */\n"
    include_anchor = "#include <pthread.h>\n"
    if text.count(include_anchor) != 1:
        raise SystemExit("Unable to locate the unique HIDAPI pthread include before Apple-mobile patching")

    header.write_text(text.replace(include_anchor, include_anchor + sentinel, 1), encoding="utf-8")
    try:
        subprocess.run([sys.executable, str(script), upstream_root], check=True)
    finally:
        cleaned = header.read_text(encoding="utf-8")
        if cleaned.count(sentinel) != 1:
            raise SystemExit("Apple-mobile HIDAPI suppression sentinel was not preserved exactly once")
        header.write_text(cleaned.replace(sentinel, "", 1), encoding="utf-8")

    final = header.read_text(encoding="utf-8")
    if final.count(RUNTIME_HID_MARKER) != 1:
        raise SystemExit("HIDAPI must retain exactly one runtime-owned iPhoneOS fallback")
    if APPLE_HID_MARKER in final or "nullptr" in final:
        raise SystemExit("Duplicate or C++-only HIDAPI fallback code remains after Apple-mobile patching")


def main() -> int:
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {Path(sys.argv[0]).name} UPSTREAM_ROOT")

    scripts = Path(__file__).resolve().parent
    port_root = scripts.parent
    upstream_root = sys.argv[1]
    patch_apple_mobile_source(port_root)
    run_patch(scripts / "patch-upstream-ios-full-qt-blockers-base.py", upstream_root)
    run_apple_mobile_patch(scripts / "patch-upstream-apple-mobile-platform.py", upstream_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
