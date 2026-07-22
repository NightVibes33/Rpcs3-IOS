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
    qt_app_root = port_root / "QtApp"
    renderer_headers = [
        port_root / "Renderers/Apple/RPCS3IOSGSFrame.h",
        port_root / "Renderers/Metal/RPCS3MetalGSRender.h",
    ]
    for source in [bridge_source, probe_source, qt_app_root / "CMakeLists.txt", *renderer_headers]:
        if not source.is_file():
            raise SystemExit(f"Missing upstream runtime/renderer input: {source}")

    cmake = upstream_root / "rpcs3/Emu/CMakeLists.txt"
    marker = "# RPCS3_IOS_UPSTREAM_RUNTIME_BRIDGE"
    text = cmake.read_text(encoding="utf-8")
    if marker in text:
        return

    # The Vulkan overlay already compiles AppleSurface, IOSGSFrame,
    # MetalRenderer, and MetalGSRender directly into rpcs3_emu. Keep this
    # bridge limited to the host callback implementation so those Objective-C++
    # objects are linked exactly once.
    text += f'''

{marker}
if(RPCS3_IOS_UPSTREAM_GRAPH)
    add_library(rpcs3_ios_upstream_bridge STATIC
        "{bridge_source.as_posix()}"
    )
    target_include_directories(rpcs3_ios_upstream_bridge PRIVATE
        "{(port_root / 'CoreBridge').as_posix()}"
        "{(port_root / 'Renderers').as_posix()}"
        "{(port_root / 'Renderers/Apple').as_posix()}"
        "{(port_root / 'Renderers/Metal').as_posix()}"
        "${{CMAKE_SOURCE_DIR}}"
        "${{CMAKE_SOURCE_DIR}}/rpcs3"
        "${{CMAKE_SOURCE_DIR}}/Utilities"
    )
    target_compile_definitions(rpcs3_ios_upstream_bridge PRIVATE
        RPCS3_IOS=1
        HAVE_VULKAN=1
        VK_USE_PLATFORM_METAL_EXT=1
    )
    target_link_libraries(rpcs3_ios_upstream_bridge PUBLIC
        rpcs3_emu
        3rdparty::vulkan
        "-framework UIKit"
        "-framework Metal"
        "-framework QuartzCore"
        "-framework Foundation"
        "-framework CoreGraphics"
        "-framework IOSurface"
    )

    add_executable(rpcs3_ios_runtime_link_probe
        "{probe_source.as_posix()}"
    )
    target_link_libraries(rpcs3_ios_runtime_link_probe PRIVATE rpcs3_ios_upstream_bridge)
    set_target_properties(rpcs3_ios_runtime_link_probe PROPERTIES
        OUTPUT_NAME "rpcs3-ios-runtime-link-probe"
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
    )

    option(RPCS3_IOS_BUILD_QT_HOST "Build the real RPCS3 Qt Widgets iOS host in this upstream graph" OFF)
    if(RPCS3_IOS_BUILD_QT_HOST)
        set(RPCS3_IOS_UNIFIED_UPSTREAM ON CACHE BOOL "" FORCE)
        add_subdirectory(
            "{qt_app_root.as_posix()}"
            "${{CMAKE_BINARY_DIR}}/rpcs3-ios-qt-host"
        )
    endif()
endif()
'''
    cmake.write_text(text, encoding="utf-8")


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
    add_runtime_bridge_targets(args.upstream_root)

    print(
        "Patched upstream emulator graph, Emu.Init bridge, UIKit GS frame, "
        f"MoltenVK, native Metal, unified Qt host, and iOS runtime dependencies: {args.upstream_root}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
