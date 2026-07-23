#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    cmake = args.upstream_root / "rpcs3/Emu/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    invalid = '        "-framework AudioUnit"\n'
    if invalid in text:
        text = text.replace(invalid, "", 1)
    elif '"-framework AudioUnit"' in text:
        raise SystemExit(f"Unexpected AudioUnit framework spelling in {cmake}")

    if '"-framework AudioToolbox"' not in text:
        raise SystemExit(f"The iOS runtime target is missing AudioToolbox in {cmake}")
    if '"-framework CoreAudio"' not in text:
        raise SystemExit(f"The iOS runtime target is missing CoreAudio in {cmake}")

    cmake.write_text(text, encoding="utf-8")
    print("Removed the unavailable standalone AudioUnit framework; iOS Audio Unit C APIs remain linked through AudioToolbox")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
