#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("port_root", type=Path)
    args = parser.parse_args()

    upstream_root = args.upstream_root.resolve()
    port_root = args.port_root.resolve()
    cmake = upstream_root / "rpcs3/Emu/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    marker = "# RPCS3_IOS_RUNTIME_LINKAGE_COMPLETION"
    if marker in text:
        print("RPCS3 iOS runtime linkage completion already present")
        return 0

    target_marker = "if(RPCS3_IOS_UPSTREAM_GRAPH)\n    enable_language(OBJCXX)"
    if target_marker not in text:
        raise SystemExit(f"Unable to locate the generated iOS runtime target in {cmake}")

    support = port_root / "CoreBridge/RPCS3IOSRuntimeSupport.cpp"
    globals_source = port_root / "CoreBridge/RPCS3IOSRuntimeGlobals.cpp"
    bridge_header = port_root / "CoreBridge/RPCS3UpstreamRuntimeBridge.h"
    required_sources = [
        support,
        globals_source,
        bridge_header,
        upstream_root / "rpcs3/Input/ps_move_config.cpp",
        upstream_root / "rpcs3/Input/ps_move_tracker.cpp",
        upstream_root / "rpcs3/Input/product_info.cpp",
        upstream_root / "rpcs3/rpcs3_version.cpp",
    ]
    for source in required_sources:
        if not source.is_file():
            raise SystemExit(f"Missing iOS runtime support source: {source}")

    block = f'''

{marker}
if(RPCS3_IOS_UPSTREAM_GRAPH)
    target_sources(rpcs3_ios_upstream_runtime PRIVATE
        "{support.as_posix()}"
        "{globals_source.as_posix()}"
        "${{CMAKE_SOURCE_DIR}}/rpcs3/Input/ps_move_config.cpp"
        "${{CMAKE_SOURCE_DIR}}/rpcs3/Input/ps_move_tracker.cpp"
        "${{CMAKE_SOURCE_DIR}}/rpcs3/Input/product_info.cpp"
        "${{CMAKE_SOURCE_DIR}}/rpcs3/rpcs3_version.cpp"
    )
    target_link_libraries(rpcs3_ios_upstream_runtime PRIVATE iconv Fusion)
    add_custom_command(TARGET rpcs3_ios_upstream_runtime POST_BUILD
        COMMAND ${{CMAKE_COMMAND}} -E make_directory
            "$<TARGET_FILE_DIR:rpcs3_ios_upstream_runtime>/Headers"
        COMMAND ${{CMAKE_COMMAND}} -E copy_if_different
            "{bridge_header.as_posix()}"
            "$<TARGET_FILE_DIR:rpcs3_ios_upstream_runtime>/Headers/RPCS3UpstreamRuntimeBridge.h"
        COMMENT "Materialize the public RPCS3 iOS runtime framework header"
    )
endif()
'''

    text += block
    cmake.write_text(text, encoding="utf-8")

    for expected in (
        "RPCS3IOSRuntimeSupport.cpp",
        "RPCS3IOSRuntimeGlobals.cpp",
        "Input/ps_move_tracker.cpp",
        "Input/product_info.cpp",
        "rpcs3_version.cpp",
        "target_link_libraries(rpcs3_ios_upstream_runtime PRIVATE iconv Fusion)",
        "Materialize the public RPCS3 iOS runtime framework header",
        "Headers/RPCS3UpstreamRuntimeBridge.h",
    ):
        if expected not in text:
            raise SystemExit(f"Runtime linkage patch verification failed: {expected}")

    print("Completed iOS runtime linkage with host callbacks, input globals, LDD pad support, Fusion motion helpers, product metadata, version helpers, iconv, and public framework header packaging")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
