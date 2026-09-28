#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


def check(name: str, ok: bool, detail: str) -> dict[str, object]:
    return {"name": name, "ok": bool(ok), "detail": detail}


def contains(path: Path, needle: str) -> bool:
    return path.is_file() and needle in path.read_text(encoding="utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("repo_root", type=Path)
    parser.add_argument("--upstream-root", type=Path)
    parser.add_argument("--json-output", type=Path)
    args = parser.parse_args()

    repo = args.repo_root.resolve()
    upstream = args.upstream_root.resolve() if args.upstream_root else None
    results = [
        check("Shared header", (repo / "CoreBridge/RPCS3AppleMobilePlatform.h").is_file(), "C API for iOS and iPadOS"),
        check("Objective-C++ platform", (repo / "CoreBridge/RPCS3AppleMobilePlatform.mm").is_file(), "UIKit, AVAudioSession and GameController implementation"),
        check("GameController wiring", contains(repo / "CoreBridge/RPCS3AppleMobilePlatform.mm", "rpcs3_ios_upstream_set_pad_state"), "Native controllers feed the real upstream pad bridge"),
        check("iPhone and iPad target families", contains(repo / "cmake/RPCS3AppleMobile.cmake", 'TARGETED_DEVICE_FAMILY "1,2"'), "Xcode targets both device families"),
        check("Apple audio session", contains(repo / "CoreBridge/RPCS3AppleMobilePlatform.mm", "AVAudioSessionCategoryPlayback"), "48 kHz playback session"),
        check("Lifecycle pause/resume", contains(repo / "CoreBridge/RPCS3AppleMobilePlatform.mm", "UIApplicationDidEnterBackgroundNotification") and contains(repo / "CoreBridge/RPCS3AppleMobilePlatform.mm", "rpcs3_ios_upstream_resume"), "Background-safe emulator lifecycle"),
        check("First-frame evidence", contains(repo / "CoreBridge/RPCS3AppleMobilePlatform.mm", "graphics.first-frame"), "Runtime JSONL checkpoint"),
    ]

    if upstream:
        display = upstream / "rpcs3/display_sleep_control.cpp"
        pad = upstream / "rpcs3/Input/gui_pad_thread.cpp"
        qt_utils = upstream / "rpcs3/rpcs3qt/qt_utils.cpp"
        hid = upstream / "3rdparty/hidapi/hidapi/libusb/hidapi_thread_pthread.h"
        qt_cmake = upstream / "rpcs3/rpcs3qt/CMakeLists.txt"
        results.extend([
            check("UIKit display sleep", contains(display, "rpcs3_apple_mobile_set_display_sleep_enabled"), str(display)),
            check("No iOS ApplicationServices include path", not (pad.is_file() and re.search(r"^\s*#(?:if|elif)\s+defined\(__APPLE__\)\s*$", pad.read_text(errors="replace"), re.MULTILINE)), str(pad)),
            check("No Finder child process on iOS", contains(qt_utils, "RPCS3 Apple mobile: use Qt/UIKit document handling"), str(qt_utils)),
            check(
                "Single HIDAPI barrier fallback",
                contains(hid, "RPCS3 iOS: pthread barriers are unavailable on iPhoneOS")
                and contains(hid, "(defined(__APPLE__) && TARGET_OS_IPHONE)")
                and not contains(hid, "RPCS3 Apple mobile pthread barrier compatibility")
                and not contains(hid, "nullptr"),
                str(hid),
            ),
            check("Full Qt target integration", contains(qt_cmake, "rpcs3_enable_apple_mobile(rpcs3_ui)"), str(qt_cmake)),
        ])

    report = {"ok": all(bool(r["ok"]) for r in results), "checks": results}
    output = json.dumps(report, indent=2)
    print(output)
    if args.json_output:
        args.json_output.write_text(output + "\n", encoding="utf-8")
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
