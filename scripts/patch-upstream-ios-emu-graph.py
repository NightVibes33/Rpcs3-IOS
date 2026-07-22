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
        'set(CMAKE_CXX_STANDARD 23)\n',
        'set(CMAKE_CXX_STANDARD 23)\n\nif(RPCS3_IOS_FULL_QT_FRONTEND)\n    add_compile_definitions(RPCS3_IOS=1)\nendif()\n',
        "iOS full frontend compile definition",
    )

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
        '''if (RPCS3_IOS_UPSTREAM_GRAPH AND NOT RPCS3_IOS_FULL_QT_FRONTEND)
    message(STATUS "RPCS3 iOS: excluding the desktop Qt host from the emulator-core graph")
elseif (NOT ANDROID)
    # The full iOS frontend lane deliberately uses RPCS3's real Qt target. Qt's
    # iOS toolchain supplies the same Widgets APIs used by the macOS build.
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
        '''if (RPCS3_IOS_UPSTREAM_GRAPH AND NOT RPCS3_IOS_FULL_QT_FRONTEND)
    message(STATUS "RPCS3 iOS: external Qt app owns the host UI in runtime-only mode")
elseif (NOT ANDROID)
    message(STATUS "RPCS3 iOS: compiling the complete upstream rpcs3_ui target")
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
        '''if (RPCS3_IOS_UPSTREAM_GRAPH AND NOT RPCS3_IOS_FULL_QT_FRONTEND)
    message(STATUS "RPCS3 iOS: rpcs3_emu is the host-linkable upstream target")
elseif (NOT ANDROID)
    if(RPCS3_IOS_FULL_QT_FRONTEND)
        message(STATUS "RPCS3 iOS: building upstream rpcs3_lib and rpcs3 executable for iOS")
    endif()
    # Build rpcs3_lib
''',
        "desktop rpcs3_lib",
    )

    replace_once(
        cmake,
        '''    elseif(APPLE)
        target_sources(rpcs3 PRIVATE rpcs3.icns update_helper.sh)
        set_source_files_properties(update_helper.sh PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
        set_target_properties(rpcs3
            PROPERTIES
                MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.plist.in")
    endif()
''',
        '''    elseif(APPLE AND RPCS3_IOS_FULL_QT_FRONTEND)
        # Qt/CMake generate an iOS bundle plist. The macOS icon, updater helper,
        # and desktop plist are intentionally not embedded in the iPhone app.
    elseif(APPLE)
        target_sources(rpcs3 PRIVATE rpcs3.icns update_helper.sh)
        set_source_files_properties(update_helper.sh PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
        set_target_properties(rpcs3
            PROPERTIES
                MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.plist.in")
    endif()
''',
        "Apple executable resources",
    )

    replace_once(
        cmake,
        '''    if(APPLE)
        qt_finalize_target(rpcs3)
        add_custom_command(TARGET rpcs3 POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.icns $<TARGET_FILE_DIR:rpcs3>/../Resources/rpcs3.icns
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_FILE_DIR:rpcs3>/../Resources/Icons
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_FILE_DIR:rpcs3>/../Resources/GuiConfigs
            COMMAND "${MACDEPLOYQT_EXECUTABLE}" "${PROJECT_BINARY_DIR}/bin/rpcs3.app" "$<$<CONFIG:Debug,RelWithDebInfo>:-no-strip>")
''',
        '''    if(APPLE AND RPCS3_IOS_FULL_QT_FRONTEND)
        qt_finalize_target(rpcs3)
        set_target_properties(rpcs3 PROPERTIES
            OUTPUT_NAME "RPCS3-iOS"
            MACOSX_BUNDLE TRUE
            MACOSX_BUNDLE_BUNDLE_NAME "RPCS3"
            MACOSX_BUNDLE_GUI_IDENTIFIER "com.nightvibes33.rpcs3ios"
            XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "com.nightvibes33.rpcs3ios"
            XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "26.0"
            XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
            XCODE_ATTRIBUTE_SUPPORTS_MACCATALYST "NO"
            XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
            XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO")
        add_custom_command(TARGET rpcs3 POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E make_directory $<TARGET_BUNDLE_CONTENT_DIR:rpcs3>/Resources
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_BUNDLE_CONTENT_DIR:rpcs3>/Resources/Icons
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_BUNDLE_CONTENT_DIR:rpcs3>/Resources/GuiConfigs)
    elseif(APPLE)
        qt_finalize_target(rpcs3)
        add_custom_command(TARGET rpcs3 POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/rpcs3.icns $<TARGET_FILE_DIR:rpcs3>/../Resources/rpcs3.icns
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/Icons $<TARGET_FILE_DIR:rpcs3>/../Resources/Icons
            COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/bin/GuiConfigs $<TARGET_FILE_DIR:rpcs3>/../Resources/GuiConfigs
            COMMAND "${MACDEPLOYQT_EXECUTABLE}" "${PROJECT_BINARY_DIR}/bin/rpcs3.app" "$<$<CONFIG:Debug,RelWithDebInfo>:-no-strip>")
''',
        "Apple deployment block",
    )


def add_runtime_bridge_targets(upstream_root: Path) -> None:
    port_root = Path(__file__).resolve().parent.parent
    bridge_source = port_root / "CoreBridge/RPCS3UpstreamRuntimeBridge.cpp"
    firmware_source = port_root / "CoreBridge/RPCS3UpstreamFirmwareInstaller.cpp"
    pad_source = port_root / "CoreBridge/RPCS3IOSPadBridge.cpp"
    bridge_header = port_root / "CoreBridge/RPCS3UpstreamRuntimeBridge.h"
    probe_source = port_root / "CoreBridge/RPCS3UpstreamRuntimeLinkProbe.cpp"
    gs_frame_header = port_root / "Port/iOS/RPCS3IOSGSFrame.h"
    gs_frame_source = port_root / "Port/iOS/RPCS3IOSGSFrame.mm"
    for source in (bridge_source, firmware_source, pad_source, bridge_header, probe_source, gs_frame_header, gs_frame_source):
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
    enable_language(OBJCXX)

    add_library(rpcs3_ios_upstream_bridge STATIC
        "{bridge_source.as_posix()}"
        "{firmware_source.as_posix()}"
        "{pad_source.as_posix()}"
    )
    target_include_directories(rpcs3_ios_upstream_bridge PUBLIC
        "{(port_root / 'CoreBridge').as_posix()}"
        "{(port_root / 'Port/iOS').as_posix()}"
        "${{CMAKE_SOURCE_DIR}}"
        "${{CMAKE_SOURCE_DIR}}/rpcs3"
    )
    target_compile_definitions(rpcs3_ios_upstream_bridge PRIVATE RPCS3_IOS=1)
    target_link_libraries(rpcs3_ios_upstream_bridge PUBLIC rpcs3_emu)
    set_target_properties(rpcs3_ios_upstream_bridge PROPERTIES
        POSITION_INDEPENDENT_CODE ON
    )

    add_library(rpcs3_ios_upstream_runtime SHARED
        "{bridge_source.as_posix()}"
        "{firmware_source.as_posix()}"
        "{pad_source.as_posix()}"
        "{gs_frame_source.as_posix()}"
    )
    set_source_files_properties("{gs_frame_source.as_posix()}" PROPERTIES
        COMPILE_OPTIONS "-fobjc-arc"
    )
    target_include_directories(rpcs3_ios_upstream_runtime PUBLIC
        "{(port_root / 'CoreBridge').as_posix()}"
        "{(port_root / 'Port/iOS').as_posix()}"
        "${{CMAKE_SOURCE_DIR}}"
        "${{CMAKE_SOURCE_DIR}}/rpcs3"
    )
    target_compile_definitions(rpcs3_ios_upstream_runtime PRIVATE RPCS3_IOS=1)
    target_link_libraries(rpcs3_ios_upstream_runtime PRIVATE
        rpcs3_emu
        "-framework Foundation"
        "-framework UIKit"
        "-framework QuartzCore"
        "-framework Metal"
        "-framework CoreGraphics"
        "-framework IOSurface"
    )
    set_target_properties(rpcs3_ios_upstream_runtime PROPERTIES
        OUTPUT_NAME "RPCS3UpstreamRuntime"
        FRAMEWORK TRUE
        FRAMEWORK_VERSION A
        MACOSX_FRAMEWORK_IDENTIFIER "com.nightvibes33.rpcs3ios.runtime"
        PUBLIC_HEADER "{bridge_header.as_posix()}"
        POSITION_INDEPENDENT_CODE ON
        XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED "NO"
        XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED "NO"
        XCODE_ATTRIBUTE_IPHONEOS_DEPLOYMENT_TARGET "26.0"
    )

    add_executable(rpcs3_ios_runtime_link_probe
        "{probe_source.as_posix()}"
    )
    target_link_libraries(rpcs3_ios_runtime_link_probe PRIVATE rpcs3_ios_upstream_runtime)
    set_target_properties(rpcs3_ios_runtime_link_probe PROPERTIES
        OUTPUT_NAME "rpcs3-ios-runtime-link-probe"
        BUILD_RPATH "@executable_path/Frameworks"
        INSTALL_RPATH "@executable_path/Frameworks"
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

    print(f"Patched upstream graph for runtime, firmware installer, touch pad, and full Qt frontend iOS lanes: {args.upstream_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
