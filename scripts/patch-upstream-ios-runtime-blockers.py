#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path
import re


TEXT_SUFFIXES = {".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx", ".mm"}


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


def patch_ffmpeg_target(upstream_root: Path, ffmpeg_root: Path) -> None:
    cmake = upstream_root / "3rdparty/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    needle = '''# FFMPEG
if(RPCS3_IOS_UPSTREAM_GRAPH)
\tmessage(STATUS "RPCS3 iOS: deferring FFmpeg until an arm64-iOS build is provided")
\tadd_library(3rdparty_ffmpeg INTERFACE)
\ttarget_compile_definitions(3rdparty_ffmpeg INTERFACE RPCS3_IOS_FFMPEG_UNAVAILABLE=1)
elseif(NOT ANDROID)
'''

    root = ffmpeg_root.resolve().as_posix()
    replacement = f'''# FFMPEG
if(RPCS3_IOS_UPSTREAM_GRAPH)
\tset(RPCS3_IOS_FFMPEG_ROOT "{root}" CACHE PATH "Pinned arm64-iOS FFmpeg install" FORCE)
\tmessage(STATUS "RPCS3 iOS: using arm64-iOS FFmpeg from ${{RPCS3_IOS_FFMPEG_ROOT}}")
\tforeach(required_file IN ITEMS
\t\tinclude/libavutil/pixfmt.h
\t\tinclude/libavcodec/avcodec.h
\t\tlib/libavformat.a
\t\tlib/libavcodec.a
\t\tlib/libavutil.a
\t\tlib/libswscale.a
\t\tlib/libswresample.a)
\t\tif(NOT EXISTS "${{RPCS3_IOS_FFMPEG_ROOT}}/${{required_file}}")
\t\t\tmessage(FATAL_ERROR "Missing iOS FFmpeg artifact: ${{RPCS3_IOS_FFMPEG_ROOT}}/${{required_file}}")
\t\tendif()
\tendforeach()
\tadd_library(3rdparty_ffmpeg INTERFACE)
\ttarget_include_directories(3rdparty_ffmpeg SYSTEM INTERFACE
\t\t"${{RPCS3_IOS_FFMPEG_ROOT}}/include")
\ttarget_link_libraries(3rdparty_ffmpeg INTERFACE
\t\t"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libavformat.a"
\t\t"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libavcodec.a"
\t\t"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libswscale.a"
\t\t"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libswresample.a"
\t\t"${{RPCS3_IOS_FFMPEG_ROOT}}/lib/libavutil.a"
\t\t"-framework CoreFoundation"
\t\t"-lm")
\ttarget_compile_definitions(3rdparty_ffmpeg INTERFACE RPCS3_IOS_FFMPEG=1)
elseif(NOT ANDROID)
'''

    if needle not in text:
        raise SystemExit("Unable to locate the RPCS3 iOS deferred FFmpeg target")
    cmake.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def verify_ffmpeg_install(ffmpeg_root: Path) -> None:
    required = [
        "include/libavutil/pixfmt.h",
        "include/libavcodec/avcodec.h",
        "lib/libavformat.a",
        "lib/libavcodec.a",
        "lib/libavutil.a",
        "lib/libswscale.a",
        "lib/libswresample.a",
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
    patched_calls = patch_desktop_jit_write_toggles(args.upstream_root)
    patch_ffmpeg_target(args.upstream_root, args.ffmpeg_root)

    print(f"Guarded {patched_calls} desktop-only JIT write-protection calls for iOS")
    print(f"Linked RPCS3's upstream graph to FFmpeg at {args.ffmpeg_root.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
