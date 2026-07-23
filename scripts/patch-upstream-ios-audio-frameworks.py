#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys


def replace_or_verify(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f"Unable to locate {label}")


def patch_runtime_target(upstream_root: Path) -> None:
    cmake = upstream_root / "rpcs3/Emu/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    framework_tokens = (
        '"-framework AudioUnit"',
        '"-framework AudioToolbox"',
        '"-framework CoreAudio"',
    )
    if not any(token in text for token in framework_tokens):
        # The interpreter-only graph does not attach audio frameworks directly
        # to rpcs3_emu; Cubeb owns that dependency graph instead. This is valid
        # and still requires the Cubeb/RtMidi corrections below.
        print(f"RPCS3 iOS runtime target has no direct audio framework block: {cmake}")
        return

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

    old = '''    target_link_libraries(cubeb PRIVATE
      "-framework AudioUnit"
      "-framework CoreAudio"
      "-framework AudioToolbox")
    list(APPEND private_libs_flags
      "-framework AudioUnit"
      "-framework CoreAudio"
      "-framework AudioToolbox")
'''
    new = '''    # iOS exposes the Audio Unit v2 C API through AudioToolbox; the device
    # SDK does not ship a standalone AudioUnit framework.
    target_link_libraries(cubeb PRIVATE
      "-framework CoreAudio"
      "-framework AudioToolbox")
    list(APPEND private_libs_flags
      "-framework CoreAudio"
      "-framework AudioToolbox")
'''
    text = replace_or_verify(text, old, new, "post-backport Cubeb iOS framework branch")
    cmake.write_text(text, encoding="utf-8")


def patch_rtmidi_target(upstream_root: Path) -> None:
    cmake = upstream_root / "3rdparty/rtmidi/rtmidi/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    old = '''if(RTMIDI_API_CORE)
  find_library(CORESERVICES_LIB CoreServices)
  find_library(COREAUDIO_LIB CoreAudio)
  find_library(COREMIDI_LIB CoreMIDI)
  find_library(COREFOUNDATION_LIB CoreFoundation)
  list(APPEND API_DEFS "-D__MACOSX_CORE__")
  list(APPEND API_LIST "coremidi")
  list(APPEND LINKLIBS ${CORESERVICES_LIB} ${COREAUDIO_LIB} ${COREMIDI_LIB} ${COREFOUNDATION_LIB})
  list(APPEND LIBS_REQUIRES "-framework CoreServices -framework CoreAudio -framework CoreMIDI -framework CoreFoundation")
  list(APPEND LINKFLAGS "-Wl,-F/Library/Frameworks")
endif()
'''
    new = '''if(RTMIDI_API_CORE)
  find_library(COREAUDIO_LIB CoreAudio)
  find_library(COREMIDI_LIB CoreMIDI)
  find_library(COREFOUNDATION_LIB CoreFoundation)
  list(APPEND API_DEFS "-D__MACOSX_CORE__")
  list(APPEND API_LIST "coremidi")
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # CoreMIDI is available on iOS without the desktop services umbrella.
    list(APPEND LINKLIBS ${COREAUDIO_LIB} ${COREMIDI_LIB} ${COREFOUNDATION_LIB})
    list(APPEND LIBS_REQUIRES "-framework CoreAudio -framework CoreMIDI -framework CoreFoundation")
  else()
    find_library(CORESERVICES_LIB CoreServices)
    list(APPEND LINKLIBS ${CORESERVICES_LIB} ${COREAUDIO_LIB} ${COREMIDI_LIB} ${COREFOUNDATION_LIB})
    list(APPEND LIBS_REQUIRES "-framework CoreServices -framework CoreAudio -framework CoreMIDI -framework CoreFoundation")
    list(APPEND LINKFLAGS "-Wl,-F/Library/Frameworks")
  endif()
endif()
'''
    text = replace_or_verify(text, old, new, "RtMidi CoreMIDI framework block")
    cmake.write_text(text, encoding="utf-8")


def complete_runtime_linkage(upstream_root: Path) -> None:
    port_root = Path(__file__).resolve().parent.parent
    script = port_root / "scripts/patch-upstream-ios-runtime-linkage.py"
    if not script.is_file():
        raise SystemExit(f"Missing runtime linkage patch: {script}")
    subprocess.run(
        [sys.executable, str(script), str(upstream_root), str(port_root)],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument(
        "--dependencies-only",
        action="store_true",
        help="Patch Cubeb/RtMidi before the generated runtime target exists",
    )
    args = parser.parse_args()
    upstream_root = args.upstream_root.resolve()

    patch_runtime_target(upstream_root)
    patch_cubeb_target(upstream_root)
    patch_rtmidi_target(upstream_root)
    if not args.dependencies_only:
        complete_runtime_linkage(upstream_root)

    mode = "dependency-only" if args.dependencies_only else "complete runtime"
    print(f"Patched iOS audio frameworks in {mode} mode")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
