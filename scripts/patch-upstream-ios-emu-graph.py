#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"Unable to locate upstream {label} block in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def main() -> int:
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    cmake = args.upstream_root / "rpcs3/CMakeLists.txt"

    replace_once(
        cmake,
        '''if (NOT ANDROID)\n    # Qt\n    # finds Qt libraries and setups custom commands for MOC and UIC\n    # Must be done here because generated MOC and UIC targets cant\n    # be found otherwise\n    include(${CMAKE_SOURCE_DIR}/3rdparty/qt6.cmake)\nendif()\n''',
        '''if (RPCS3_IOS_UPSTREAM_GRAPH)\n    message(STATUS "RPCS3 iOS: excluding desktop Qt from the emulator-core graph")\nelseif (NOT ANDROID)\n    # Qt\n    # finds Qt libraries and setups custom commands for MOC and UIC\n    # Must be done here because generated MOC and UIC targets cant\n    # be found otherwise\n    include(${CMAKE_SOURCE_DIR}/3rdparty/qt6.cmake)\nendif()\n''',
        "Qt setup",
    )

    replace_once(
        cmake,
        '''if (NOT ANDROID)\n    add_subdirectory(rpcs3qt)\nendif()\n''',
        '''if (RPCS3_IOS_UPSTREAM_GRAPH)\n    message(STATUS "RPCS3 iOS: UIKit owns the host UI; preserving rpcs3/Emu only")\nelseif (NOT ANDROID)\n    add_subdirectory(rpcs3qt)\nendif()\n''',
        "rpcs3qt subdirectory",
    )

    replace_once(
        cmake,
        '''if (NOT ANDROID)\n    # Build rpcs3_lib\n''',
        '''if (RPCS3_IOS_UPSTREAM_GRAPH)\n    message(STATUS "RPCS3 iOS: rpcs3_emu is the host-linkable upstream target")\nelseif (NOT ANDROID)\n    # Build rpcs3_lib\n''',
        "desktop rpcs3_lib",
    )

    print(f"Patched upstream emulator graph for iOS: {cmake}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
