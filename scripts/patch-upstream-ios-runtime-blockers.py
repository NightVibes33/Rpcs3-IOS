#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import re
import subprocess
import sys


TEXT_SUFFIXES = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".mm"}


def patch_port_v0040_compatibility() -> None:
    """Keep every upstream lane on the pinned v0.0.40 no-exceptions ABI."""
    port_root = Path(__file__).resolve().parent.parent
    patcher = port_root / "scripts/patch-upstream-ios-v0040-compat.py"
    if not patcher.is_file():
        raise SystemExit(f"Missing v0.0.40 compatibility patch: {patcher}")
    subprocess.run([sys.executable, str(patcher), str(port_root)], check=True)


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"Unable to locate upstream {label} block in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_non_llvm_aarch64_backend(upstream_root: Path) -> None:
    """Keep the ARM64 host helpers, but omit LLVM-only sources in interpreter builds."""
    cmake = upstream_root / "rpcs3/Emu/CMakeLists.txt"
    needle = '''if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64|aarch64")
    target_sources(rpcs3_emu PRIVATE
        CPU/Backends/AArch64/AArch64ASM.cpp
        CPU/Backends/AArch64/AArch64Common.cpp
        CPU/Backends/AArch64/AArch64JIT.cpp
        CPU/Backends/AArch64/AArch64Signal.cpp
    )
endif()
'''
    replacement = '''if(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|arm64|aarch64")
    target_sources(rpcs3_emu PRIVATE
        CPU/Backends/AArch64/AArch64Common.cpp
        CPU/Backends/AArch64/AArch64Signal.cpp
    )
    if(WITH_LLVM)
        target_sources(rpcs3_emu PRIVATE
            CPU/Backends/AArch64/AArch64ASM.cpp
            CPU/Backends/AArch64/AArch64JIT.cpp
        )
    else()
        message(STATUS "RPCS3 iOS: omitting LLVM-only AArch64ASM/AArch64JIT sources")
    endif()
endif()
'''
    replace_once(cmake, needle, replacement, "ARM64 backend source list")


def patch_ios_hidapi_backend(upstream_root: Path) -> None:
    """Use HIDAPI's libusb backend because iPhoneOS has no macOS IOHIDManager headers."""
    wrapper = upstream_root / "3rdparty/hidapi/CMakeLists.txt"
    wrapper_text = wrapper.read_text(encoding="utf-8")
    wrapper_text = wrapper_text.replace(
        "\tadd_library(3rdparty_hidapi INTERFACE)\n\tadd_subdirectory(hidapi EXCLUDE_FROM_ALL)\n",
        "\tif(CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
        "\t\tset(HIDAPI_NO_ICONV ON CACHE BOOL \"iOS uses the libusb HID backend without iconv\" FORCE)\n"
        "\tendif()\n\n"
        "\tadd_library(3rdparty_hidapi INTERFACE)\n\tadd_subdirectory(hidapi EXCLUDE_FROM_ALL)\n",
        1,
    )
    wrapper_text = wrapper_text.replace(
        "\tif(APPLE)\n\t\ttarget_link_libraries(3rdparty_hidapi INTERFACE hidapi_darwin \"-framework CoreFoundation\" \"-framework IOKit\")\n\telseif(CMAKE_SYSTEM MATCHES \"Linux\")",
        "\tif(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
        "\t\ttarget_link_libraries(3rdparty_hidapi INTERFACE hidapi_darwin \"-framework CoreFoundation\" \"-framework IOKit\")\n"
        "\telseif(CMAKE_SYSTEM_NAME STREQUAL \"iOS\")\n"
        "\t\ttarget_link_libraries(3rdparty_hidapi INTERFACE hidapi::libusb)\n"
        "\telseif(CMAKE_SYSTEM MATCHES \"Linux\")",
        1,
    )
    required_wrapper = (
        'set(HIDAPI_NO_ICONV ON CACHE BOOL "iOS uses the libusb HID backend without iconv" FORCE)',
        'APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS"',
        'target_link_libraries(3rdparty_hidapi INTERFACE hidapi::libusb)',
    )
    for marker in required_wrapper:
        if marker not in wrapper_text:
            raise SystemExit(f"Unable to patch iOS HIDAPI wrapper marker: {marker}")
    wrapper.write_text(wrapper_text, encoding="utf-8")

    source_cmake = upstream_root / "3rdparty/hidapi/hidapi/src/CMakeLists.txt"
    source_text = source_cmake.read_text(encoding="utf-8")
    needle = "elseif(APPLE)\n"
    replacement = 'elseif(APPLE AND NOT CMAKE_SYSTEM_NAME STREQUAL "iOS")\n'
    if needle not in source_text:
        raise SystemExit("Unable to locate HIDAPI Apple backend selector")
    source_cmake.write_text(source_text.replace(needle, replacement, 1), encoding="utf-8")

    barrier_header = upstream_root / "3rdparty/hidapi/hidapi/libusb/hidapi_thread_pthread.h"
    barrier_text = barrier_header.read_text(encoding="utf-8")
    barrier_marker = "RPCS3 iOS: pthread barriers are unavailable on iPhoneOS"
    if barrier_marker not in barrier_text:
        barrier_needle = """#include <pthread.h>

#if defined(__ANDROID__) && __ANDROID_API__ < __ANDROID_API_N__
"""
        barrier_replacement = """#include <pthread.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

/* RPCS3 iOS: pthread barriers are unavailable on iPhoneOS. Reuse HIDAPI's
   mutex/condition fallback that is already used on older Android releases. */
#if (defined(__ANDROID__) && __ANDROID_API__ < __ANDROID_API_N__) || \
    (defined(__APPLE__) && TARGET_OS_IPHONE)
"""
        if barrier_needle not in barrier_text:
            raise SystemExit("Unable to locate HIDAPI pthread barrier fallback guard")
        barrier_header.write_text(
            barrier_text.replace(barrier_needle, barrier_replacement, 1),
            encoding="utf-8",
        )


def patch_desktop_jit_write_toggles(upstream_root: Path) -> int:
    """Remove desktop-only pthread JIT write toggles from the iOS interpreter lane.

    iOS marks pthread_jit_write_protect_np unavailable to ordinary applications.
    The upstream-graph probe deliberately builds with LLVM disabled, so these
    toggles must not be emitted. This does not claim or simulate JIT access.
    """

    pattern = re.compile(
        r"^(?P<indent>[ \t]*)pthread_jit_write_protect_np\((?P<value>[^;\n]+)\);(?P<trailing>[ \t]*)$",
        re.MULTILINE,
    )
    patched_calls = 0

    for path in upstream_root.rglob("*"):
        if not path.is_file() or path.suffix not in TEXT_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        if "pthread_jit_write_protect_np(" not in text:
            continue

        def replace(match: re.Match[str]) -> str:
            nonlocal patched_calls
            patched_calls += 1
            indent = match.group("indent")
            value = match.group("value")
            trailing = match.group("trailing")
            return (
                f"{indent}#if defined(__APPLE__) && !defined(RPCS3_IOS)\n"
                f"{indent}pthread_jit_write_protect_np({value});{trailing}\n"
                f"{indent}#endif"
            )

        updated = pattern.sub(replace, text)
        if updated != text:
            path.write_text(updated, encoding="utf-8")

    if patched_calls == 0:
        raise SystemExit("No standalone pthread_jit_write_protect_np calls were patched")
    return patched_calls


def patch_ios_config_dir(upstream_root: Path) -> None:
    source = upstream_root / "Utilities/File.cpp"
    text = source.read_text(encoding="utf-8")
    marker = "RPCS3 iOS: honor RPCS3_CONFIG_DIR as the complete data root"
    if marker in text:
        return
    needle = '''#else

#ifdef __APPLE__
		if (const char* home = ::getenv("HOME"))
			dir = home + "/Library/Application Support"s;
#else
		if (const char* conf = ::getenv("XDG_CONFIG_HOME"))
			dir = conf;
		else if (const char* home = ::getenv("HOME"))
			dir = home + "/.config"s;
#endif
		else // Just in case
			dir = "./config";

		dir += "/rpcs3/";

		if (!create_path(dir))
'''
    replacement = '''#else
		// RPCS3 iOS: honor RPCS3_CONFIG_DIR as the complete data root.
		bool append_product_directory = true;
#if defined(RPCS3_IOS)
		if (const char* override_dir = ::getenv("RPCS3_CONFIG_DIR"); override_dir && *override_dir)
		{
			dir = override_dir;
			append_product_directory = false;
		}
#endif

		if (dir.empty())
		{
#ifdef __APPLE__
			if (const char* home = ::getenv("HOME"))
				dir = home + "/Library/Application Support"s;
#else
			if (const char* conf = ::getenv("XDG_CONFIG_HOME"))
				dir = conf;
			else if (const char* home = ::getenv("HOME"))
				dir = home + "/.config"s;
#endif
			else // Just in case
				dir = "./config";
		}

		if (append_product_directory)
		{
			dir += "/rpcs3/";
		}
		else if (!dir.empty() && dir.back() != '/')
		{
			dir += '/';
		}

		if (!create_path(dir))
'''
    if needle not in text:
        raise SystemExit("Unable to locate upstream Apple configuration-directory block")
    source.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_ios_metal_surface(upstream_root: Path) -> None:
    source = upstream_root / "rpcs3/Emu/RSX/VK/vkutils/metal_layer.mm"
    text = source.read_text(encoding="utf-8")
    marker = "RPCS3 iOS CAMetalLayer handle"
    if marker in text:
        return
    needle = '''#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-declarations"
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>

void* GetCAMetalLayerFromMetalView(void* view) { return ((NSView*)view).layer; }
#pragma GCC diagnostic pop
'''
    replacement = '''#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-declarations"
#import <Foundation/Foundation.h>
#import <TargetConditionals.h>
#import <QuartzCore/QuartzCore.h>

#if TARGET_OS_IPHONE
// RPCS3 iOS CAMetalLayer handle: GSFrameBase::handle() already returns the
// layer owned by the native Qt render host, not a UIView wrapper.
void* GetCAMetalLayerFromMetalView(void* layer) { return layer; }
#else
#import <AppKit/AppKit.h>
void* GetCAMetalLayerFromMetalView(void* view) { return ((NSView*)view).layer; }
#endif
#pragma GCC diagnostic pop
'''
    if needle not in text:
        raise SystemExit("Unable to locate upstream macOS metal_layer.mm implementation")
    source.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_ffmpeg_target(upstream_root: Path, ffmpeg_root: Path) -> None:
    cmake = upstream_root / "3rdparty/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    needle = '''# FFMPEG
if(RPCS3_IOS_UPSTREAM_GRAPH)
	message(STATUS "RPCS3 iOS: deferring FFmpeg until an arm64-iOS build is provided")
	add_library(3rdparty_ffmpeg INTERFACE)
	target_compile_definitions(3rdparty_ffmpeg INTERFACE RPCS3_IOS_FFMPEG_UNAVAILABLE=1)
elseif(NOT ANDROID)
'''
    root = ffmpeg_root.resolve().as_posix()
    replacement = f'''# FFMPEG
if(RPCS3_IOS_UPSTREAM_GRAPH)
	set(RPCS3_IOS_FFMPEG_ROOT "{root}" CACHE PATH "Pinned arm64-iOS FFmpeg install" FORCE)
	message(STATUS "RPCS3 iOS: using arm64-iOS FFmpeg from ${{RPCS3_IOS_FFMPEG_ROOT}}")
	foreach(required_file IN ITEMS
		include/libavutil/pixfmt.h
		include/libavcodec/avcodec.h
		lib/libavformat.a
		lib/libavcodec.a
		lib/libavutil.a
		lib/libswscale.a
		lib/libswresample.a)
		if(NOT EXISTS "${{RPCS3_IOS_FFMPEG_ROOT}}/${{required_file}}")
			message(FATAL_ERROR "Missing iOS FFmpeg artifact: ${{RPCS3_IOS_FFMPEG_ROOT}}/${{required_file}}")
		endif()
	endforeach()
	add_library(3rdparty_ffmpeg INTERFACE)
	target_include_directories(3rdparty_ffmpeg SYSTEM INTERFACE
		"${{RPCS3_IOS_FFMPEG_ROOT}}/include")
	target_link_libraries(3rdparty_ffmpeg INTERFACE
		"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libavformat.a"
		"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libavcodec.a"
		"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libswscale.a"
		"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libswresample.a"
		"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libavutil.a"
		"-framework CoreFoundation"
		"-lm")
	target_compile_definitions(3rdparty_ffmpeg INTERFACE RPCS3_IOS_FFMPEG=1)
elseif(NOT ANDROID)
'''
    if nedle not in text:
        raise SystemExit("Unable to locate the RPCS3 iOS deferred FFmpeg target")
    cmake.write_text(text.replace(nedle, replacement, 1), encoding="utf-8")


def verify_ffmpeg_install(ffmpeg_root: Path) -> None:
    required = [
        "include/libavutil/pixfmt.h", "include/libavcodec/avcodec.h",
        "lib/libavformat.a", "lib/libavcodec.a", "lib/libavutil.a",
        "lib/libswscale.a", "lib/libswresample.a",
    ]
    missing = [name for name in required if not (ffmpeg_root / name).is_file()]
    if missing:
        raise SystemExit(f"Incomplete arm64-iOS FFmpeg install at {ffmpeg_root}: {missing}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("ffmpeg_root", type=Path)
    args = parser.parse_args()

    verify_ffmpeg_install(args.ffmpeg_root)
    patch_port_v0040_compatibility()
    patch_non_llvm_aarch64_backend(args.upstream_root)
    patch_ios_hidapi_backend(args.upstream_root)
    patched_calls = patch_desktop_jit_write_toggles(args.upstream_root)
    patch_ios_config_dir(args.upstream_root)
    patch_ios_metal_surface(args.upstream_root)
    patch_ffmpeg_target(args.upstream_root, args.ffmpeg_root)

    print("Applied the pinned RPCS3 v0.0.40 bridge and no-exceptions compatibility patch")
    print("Excluded LLVM-only ARM64 backend sources from interpreter-only iOS builds")
    print("Selected HIDAPI libusb backend and pthread barrier fallback for iOS")
    print(f"Guarded {patched_calls} desktop-only JIT write-protection calls for iOS")
    print("Made RPCS3_CONFIG_DIR authoritative for the shared iOS dev_hdd0/dev_flash tree")
    print("Patched RPCS3's Apple Vulkan WSI helper to consume the iOS CAMetalLayer handle")
    print(f"Linked RPCS3's upstream graph to FFmpeg at {args.ffmpeg_root.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
