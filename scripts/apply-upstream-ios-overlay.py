#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

MARKER = "# BEGIN RPCS3-IOS OVERLAY"


def block(mode: str) -> str:
    if mode == "bootstrap":
        body = '''option(RPCS3_IOS_CORE_ONLY "Build only the RPCS3 iOS bootstrap static core" OFF)
if(RPCS3_IOS_CORE_ONLY)
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
        message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point to the iOS port repository")
    endif()
    add_compile_definitions(
        RPCS3_IOS=1
        RPCS3_PLATFORM_MOBILE=1
        RPCS3_PLATFORM_DESKTOP=0
    )
    add_subdirectory(
        "${RPCS3_IOS_PORT_ROOT}/Port"
        "${CMAKE_BINARY_DIR}/rpcs3-ios-port"
    )
    return()
endif()
'''
    else:
        body = '''option(RPCS3_IOS_UPSTREAM_GRAPH "Configure RPCS3's real upstream build graph for iOS" OFF)
if(RPCS3_IOS_UPSTREAM_GRAPH)
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
        message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point to the iOS port repository")
    endif()
    add_compile_definitions(
        RPCS3_IOS=1
        RPCS3_PLATFORM_MOBILE=1
        RPCS3_PLATFORM_DESKTOP=0
    )
    set(USE_FAUDIO OFF CACHE BOOL "" FORCE)
    set(USE_NATIVE_INSTRUCTIONS OFF CACHE BOOL "" FORCE)
    set(USE_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
    set(BUILD_LLVM_SUBMODULE OFF CACHE BOOL "" FORCE)
    message(STATUS "RPCS3 iOS: entering the real upstream dependency and emulator graph")
endif()
'''
    return f"{MARKER}\n{body}# END RPCS3-IOS OVERLAY\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("--mode", choices=("bootstrap", "upstream"), default="bootstrap")
    args = parser.parse_args()

    cmake = args.upstream_root / "CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"iOS overlay already present in {cmake}")
        return 0

    needle = "project(rpcs3 LANGUAGES C CXX)\n"
    if needle not in text:
        raise SystemExit("Unable to locate the upstream RPCS3 project declaration")

    cmake.write_text(text.replace(needle, needle + "\n" + block(args.mode), 1), encoding="utf-8")
    print(f"Applied {args.mode} iOS overlay to {cmake}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
