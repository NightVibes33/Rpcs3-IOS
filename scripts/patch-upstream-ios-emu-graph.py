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


def add_runtime_bridge_targets(upstream_root: Path) -> None:
    port_root = Path(__file__).resolve().parent.parent
    bridge_source = port_root / "CoreBridge/RPCS3UpstreamRuntimeBridge.cpp"
    probe_source = port_root / "CoreBridge/RPCS3UpstreamRuntimeLinkProbe.cpp"
    for source in (bridge_source, probe_source):
        if not source.is_file():
            raise SystemExit(f"Missing upstream runtime bridge source: {source}")

    cmake = upstream_root / "rpcs3/Emu/CMakeLists.txt"
    marker = "# RPCS3_IOS_UPSTREAM_RUNTIME_BRIDGE"
    text = cmake.read_text(encoding="utf-8")
    if marker in text:
        return

    text += f'''

{marker}
if(RPCS3_IOS_UPSTREAM_GRAPH)
    add_library(rpcs3_ios_upstream_bridge STATIC
        "{bridge_source.as_posix()}"
    )
    target_include_directories(rpcs3_ios_upstream_bridge PRIVATE
        "{(port_root / 'CoreBridge').as_posix()}"
        "${{CMAKE_SOURCE_DIR}}"
        "${{CMAKE_SOURCE_DIR}}/rpcs3"
    )
    target_compile_definitions(rpcs3_ios_upstream_bridge PRIVATE RPCS3_IOS=1)
    target_link_libraries(rpcs3_ios_upstream_bridge PUBLIC rpcs3_emu)

    add_executable(rpcs3_ios_runtime_link_probe
        "{probe_source.as_posix()}"
    )
    target_link_libraries(rpcs3_ios_runtime_link_probe PRIVATE rpcs3_ios_upstream_bridge)
    set_target_properties(rpcs3_ios_runtime_link_probe PROPERTIES
        OUTPUT_NAME "rpcs3-ios-runtime-link-probe"
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    )
endif()
'''
    cmake.write_text(text, encoding="utf-8")


def patch_ios_runtime_dependencies(upstream_root: Path) -> None:
    port_root = Path(__file__).resolve().parent.parent
    ffmpeg_root = Path(
        os.environ.get("RPCS3_IOS_FFMPEG_ROOT", port_root / "BuildSupport/ffmpeg-ios")
    ).resolve()
    runtime_patch = port_root / "scripts/patch-upstream-ios-runtime-blockers.py"

    if not runtime_patch.is_file():
        raise SystemExit(f"Missing runtime blocker patch: {runtime_patch}")

    subprocess.run(
        [sys.executable, str(runtime_patch), str(upstream_root), str(ffmpeg_root)],
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
    add_runtime_bridge_targets(args.upstream_root)

    print(f"Patched upstream emulator graph, runtime dependencies, and Emu.Init link probe: {args.upstream_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
