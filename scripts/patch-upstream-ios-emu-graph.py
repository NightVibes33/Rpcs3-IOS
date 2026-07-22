#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"Unable to locate upstream {label} block in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_top_level_graph(upstream_root: Path) -> None:
    cmake = upstream_root / "rpcs3/CMakeLists.txt"

    replace_once(
        cmake,
        '''if (NOT ANDROID)
    # Qt
    # finds Qt libraries and setups custom commands for MOC and UIC
    # Must be done here because generated MOC and UIC targets cant
    # be found otherwise
    include(${CMAKE_SOURCE_DIR}/3rdparty/qt6.cmake)
endif()
''',
        '''if (RPCS3_IOS_UPSTREAM_GRAPH)
    message(STATUS "RPCS3 iOS: excluding the desktop Qt host from the emulator-core graph")
elseif (NOT ANDROID)
    # Qt
    # finds Qt libraries and setups custom commands for MOC and UIC
    # Must be done here because generated MOC and UIC targets cant
    # be found otherwise
    include(${CMAKE_SOURCE_DIR}/3rdparty/qt6.cmake)
endif()
''',
        "Qt setup",
    )

    replace_once(
        cmake,
        '''if (NOT ANDROID)
    add_subdirectory(rpcs3qt)
endif()
''',
        '''if (RPCS3_IOS_UPSTREAM_GRAPH)
    message(STATUS "RPCS3 iOS: the external Qt iOS app owns the host UI; preserving rpcs3/Emu")
elseif (NOT ANDROID)
    add_subdirectory(rpcs3qt)
endif()
''',
        "rpcs3qt subdirectory",
    )

    replace_once(
        cmake,
        '''if (NOT ANDROID)
    # Build rpcs3_lib
''',
        '''if (RPCS3_IOS_UPSTREAM_GRAPH)
    message(STATUS "RPCS3 iOS: rpcs3_emu is the host-linkable upstream target")
elseif (NOT ANDROID)
    # Build rpcs3_lib
''',
        "desktop rpcs3_lib",
    )


def patch_ios_jit_write_protection(upstream_root: Path) -> None:
    """Do not call the macOS-only pthread JIT toggle while compiling for iOS.

    The interpreter-first graph still keeps RPCS3's asmjit source in the target,
    but iOS marks pthread_jit_write_protect_np unavailable. Executable-memory
    enablement remains a separate entitlement/runtime task and is not faked here.
    """
    header = upstream_root / "Utilities/JIT.h"
    replace_once(
        header,
        '''#ifdef __APPLE__
	pthread_jit_write_protect_np(false);
#endif
''',
        '''#if defined(__APPLE__) && !defined(RPCS3_IOS)
	pthread_jit_write_protect_np(false);
#endif
''',
        "Apple pthread JIT write-protection call",
    )


def expose_ffmpeg_headers_for_static_graph(upstream_root: Path) -> None:
    """Expose the pinned FFmpeg headers while keeping desktop archives unlinked.

    rpcs3_emu is a static target, so this phase needs the exact upstream headers
    to compile System.cpp and RSX declarations but does not yet need to resolve
    FFmpeg symbols into a final executable. A real arm64-iOS FFmpeg archive is
    still required before the emulator target can be linked into the app.
    """
    cmake = upstream_root / "3rdparty/CMakeLists.txt"
    replace_once(
        cmake,
        '''	add_library(3rdparty_ffmpeg INTERFACE)
	target_compile_definitions(3rdparty_ffmpeg INTERFACE RPCS3_IOS_FFMPEG_UNAVAILABLE=1)
''',
        '''	add_library(3rdparty_ffmpeg INTERFACE)
	target_include_directories(3rdparty_ffmpeg SYSTEM INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/ffmpeg/include")
	target_compile_definitions(3rdparty_ffmpeg INTERFACE RPCS3_IOS_FFMPEG_UNAVAILABLE=1)
''',
        "iOS deferred FFmpeg target",
    )


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    patch_top_level_graph(args.upstream_root)
    patch_ios_jit_write_protection(args.upstream_root)
    expose_ffmpeg_headers_for_static_graph(args.upstream_root)

    print(f"Patched upstream emulator graph and current iOS compile blockers: {args.upstream_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
