#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if needle not in text:
        raise SystemExit(f"Unable to locate {label} in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_cmake(port_root: Path) -> None:
    cmake = port_root / "QtApp/CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")

    if "set(CMAKE_CXX_STANDARD 20)" in text:
        text = text.replace("set(CMAKE_CXX_STANDARD 20)", "set(CMAKE_CXX_STANDARD 23)", 1)
    elif "set(CMAKE_CXX_STANDARD 23)" not in text:
        raise SystemExit(f"Unable to identify the Qt host C++ standard in {cmake}")

    link_marker = 'rpcs3_link_moltenvk(RPCS3QtIOS "${RPCS3_IOS_MOLTENVK_ROOT}")\n'
    link_options = (
        link_marker
        + "\n# MoltenVK is a static Objective-C++ archive. Keep its Objective-C classes\n"
        + "# and categories reachable from the final iOS executable.\n"
        + 'target_link_options(RPCS3QtIOS PRIVATE "-ObjC")\n'
    )
    if 'target_link_options(RPCS3QtIOS PRIVATE "-ObjC")' not in text:
        if link_marker not in text:
            raise SystemExit(f"Unable to locate MoltenVK linkage in {cmake}")
        text = text.replace(link_marker, link_options, 1)

    cmake.write_text(text, encoding="utf-8")


def patch_main(port_root: Path) -> None:
    main = port_root / "QtApp/main.cpp"
    text = main.read_text(encoding="utf-8")

    include_line = '#include "RPCS3RuntimeActionOverrides.h"\n'
    if include_line not in text:
        anchor = '#include "RPCS3RendererIntegration.h"\n'
        if anchor not in text:
            raise SystemExit(f"Unable to locate renderer integration include in {main}")
        text = text.replace(anchor, anchor + include_line, 1)

    call = "    RPCS3InstallRuntimeActionOverrides(&window);\n"
    if call not in text:
        anchor = "    RPCS3InstallRendererIntegration(&window);\n"
        if anchor not in text:
            raise SystemExit(f"Unable to locate renderer integration call in {main}")
        text = text.replace(anchor, anchor + call, 1)

    main.write_text(text, encoding="utf-8")


def main() -> int:
    port_root = Path(__file__).resolve().parent.parent
    patch_cmake(port_root)
    patch_main(port_root)
    print(f"Patched unified Qt host in {port_root}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
