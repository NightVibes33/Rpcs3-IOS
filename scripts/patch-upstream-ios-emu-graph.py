#!/usr/bin/env python3
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys


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
    message(STATUS "RPCS3 iOS: the external Qt Widgets iOS app owns the host UI; preserving rpcs3/Emu")
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


def patch_ios_runtime_dependencies(upstream_root: Path) -> None:
    port_root = Path(__file__).resolve().parent.parent
    ffmpeg_root = Path(
        os.environ.get("RPCS3_IOS_FFMPEG_ROOT", port_root / "BuildSupport/ffmpeg-ios")
    ).resolve()
    moltenvk_root = Path(
        os.environ.get("RPCS3_IOS_MOLTENVK_ROOT", port_root / "BuildSupport/MoltenVK")
    ).resolve()
    runtime_patch = port_root / "scripts/patch-upstream-ios-runtime-blockers.py"
    objcxx_patch = port_root / "scripts/patch-upstream-ios-objcxx.py"
    vulkan_patch = port_root / "scripts/patch-upstream-ios-vulkan.py"

    for required in (runtime_patch, objcxx_patch, vulkan_patch):
        if not required.is_file():
            raise SystemExit(f"Missing upstream patch: {required}")

    subprocess.run(
        [sys.executable, str(runtime_patch), str(upstream_root), str(ffmpeg_root)],
        check=True,
        env=os.environ.copy(),
    )
    subprocess.run(
        [sys.executable, str(objcxx_patch), str(upstream_root)],
        check=True,
        env=os.environ.copy(),
    )
    subprocess.run(
        [sys.executable, str(vulkan_patch), str(upstream_root), str(moltenvk_root)],
        check=True,
        env=os.environ.copy(),
    )


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    patch_top_level_graph(args.upstream_root)
    patch_ios_runtime_dependencies(args.upstream_root)

    print(f"Patched upstream emulator graph, Objective-C++, Vulkan, Metal, and iOS runtime dependencies: {args.upstream_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
