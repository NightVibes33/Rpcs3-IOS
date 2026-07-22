#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    upstream_root = args.upstream_root.resolve()
    port_root = Path(__file__).resolve().parent.parent
    cmake = upstream_root / "CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    marker = "# RPCS3 iOS upstream runtime bridge targets"
    if marker not in text:
        raise SystemExit(f"The runtime bridge block was not generated in {cmake}")

    runtime_bridge = (port_root / "CoreBridge/RPCS3UpstreamRuntimeBridge.cpp").as_posix()
    source_pattern = re.compile(
        r"set\(RPCS3_IOS_UPSTREAM_BRIDGE_SOURCES\n.*?\n    \)\n",
        re.DOTALL,
    )
    source_replacement = (
        "set(RPCS3_IOS_UPSTREAM_BRIDGE_SOURCES\n"
        f'        "{runtime_bridge}"\n'
        "    )\n"
    )
    text, source_count = source_pattern.subn(source_replacement, text, count=1)
    if source_count != 1:
        raise SystemExit("Unable to replace the generated runtime bridge source list")

    properties_pattern = re.compile(
        r"    set_source_files_properties\(\n"
        r"        \".*?RPCS3AppleSurface\.mm\"\n"
        r"        \".*?RPCS3IOSGSFrame\.mm\"\n"
        r"        \".*?RPCS3MetalRenderer\.mm\"\n"
        r"        \".*?RPCS3MetalGSRender\.mm\"\n"
        r"        PROPERTIES COMPILE_OPTIONS \"-fobjc-arc\"\n"
        r"    \)\n",
        re.DOTALL,
    )
    text, properties_count = properties_pattern.subn("", text, count=1)
    if properties_count != 1:
        raise SystemExit("Unable to remove duplicate renderer ARC source properties")

    cmake.write_text(text, encoding="utf-8")
    print(f"Deduplicated renderer implementations in {cmake}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
