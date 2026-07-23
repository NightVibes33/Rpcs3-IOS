#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def replace_or_verify(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f"Unable to locate {label}")


def patch_runtime_target(upstream_root: Path) -> None:
    cmake = upstream_root / "rpcs3/Emu/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    invalid = '        "-framework AudioUnit"\n'
    if invalid in text:
        text = text.replace(invalid, "", 1)
    elif '"-framework AudioUnit"' in text:
        raise SystemExit(f"Unexpected AudioUnit framework spelling in {cmake}")

    if '"-framework AudioToolbox"' not in text:
        raise SystemExit(f"The iOS runtime target is missing AudioToolbox in {cmake}")
    if '"-framework CoreAudio"' not in text:
        raise SystemExit(f"The iOS runtime target is missing CoreAudio in {cmake}")

    cmake.write_text(text, encoding="utf-8")


def patch_cubeb_target(upstream_root: Path) -> None:
    cmake = upstream_root / "3rdparty/cubeb/cubeb/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    old = '''  target_link_libraries(cubeb PRIVATE "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")
  list(APPEND private_libs_flags "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")
'''
    new = '''  # iOS exposes the Audio Unit v2 C API through AudioToolbox. The standalone
  # AudioUnit and CoreServices frameworks are macOS-only in the device SDK.
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    target_link_libraries(cubeb PRIVATE "-framework AudioToolbox" "-framework CoreAudio")
    list(APPEND private_libs_flags "-framework AudioToolbox" "-framework CoreAudio")
  else()
    target_link_libraries(cubeb PRIVATE "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")
    list(APPEND private_libs_flags "-framework AudioUnit" "-framework CoreAudio" "-framework CoreServices")
  endif()
'''
    text = replace_or_verify(text, old, new, "Cubeb Apple audio framework block")
    cmake.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()
    upstream_root = args.upstream_root.resolve()

    patch_runtime_target(upstream_root)
    patch_cubeb_target(upstream_root)

    print("Patched the iOS runtime and Cubeb to use AudioToolbox/CoreAudio without macOS-only AudioUnit/CoreServices frameworks")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
