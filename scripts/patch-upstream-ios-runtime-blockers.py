#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
from pathlib import Path
import subprocess
import sys


def load_base_module():
    path = Path(__file__).with_name("patch-upstream-ios-runtime-blockers-base.py")
    spec = importlib.util.spec_from_file_location("rpcs3_ios_runtime_blockers_base", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Unable to load runtime blocker base module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def patch_port_v0040_compatibility() -> None:
    port_root = Path(__file__).resolve().parent.parent
    patcher = port_root / "scripts/patch-upstream-ios-v0040-compat.py"
    if not patcher.is_file():
        raise SystemExit(f"Missing v0.0.40 compatibility patch: {patcher}")
    subprocess.run([sys.executable, str(patcher), str(port_root)], check=True)


def patch_ios_hidapi_barrier(upstream_root: Path) -> None:
    header = upstream_root / "3rdparty/hidapi/hidapi/libusb/hidapi_thread_pthread.h"
    text = header.read_text(encoding="utf-8")
    marker = "RPCS3 iOS: pthread barriers are unavailable on iPhoneOS"
    if marker in text:
        return

    needle = """#include <pthread.h>

#if defined(__ANDROID__) && __ANDROID_API__ < __ANDROID_API_N__
"""
    replacement = """#include <pthread.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

/* RPCS3 iOS: pthread barriers are unavailable on iPhoneOS. Reuse HIDAPI's
   mutex/condition fallback that is already used on older Android releases. */
#if (defined(__ANDROID__) && __ANDROID_API__ < __ANDROID_API_N__) || \
    (defined(__APPLE__) && TARGET_OS_IPHONE)
"""
    if needle not in text:
        raise SystemExit("Unable to locate HIDAPI pthread barrier fallback guard")
    header.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def main() -> int:
    if len(sys.argv) != 3:
        raise SystemExit("usage: patch-upstream-ios-runtime-blockers.py <upstream_root> <ffmpeg_root>")

    patch_port_v0040_compatibility()
    base = load_base_module()
    status = int(base.main())
    patch_ios_hidapi_barrier(Path(sys.argv[1]))
    print("Applied HIDAPI's pthread barrier fallback for iPhoneOS")
    return status


if __name__ == "__main__":
    raise SystemExit(main())
