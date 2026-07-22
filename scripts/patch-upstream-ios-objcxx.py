#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    cmake = args.upstream_root.resolve() / "CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    needle = '''if(RPCS3_IOS_UPSTREAM_GRAPH)
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
'''
    replacement = '''if(RPCS3_IOS_UPSTREAM_GRAPH)
    enable_language(OBJCXX)
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
'''
    if needle not in text:
        raise SystemExit(f"Unable to locate the RPCS3 iOS upstream graph block in {cmake}")
    cmake.write_text(text.replace(needle, replacement, 1), encoding="utf-8")
    print(f"Enabled Objective-C++ in the upstream iOS graph: {cmake}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
