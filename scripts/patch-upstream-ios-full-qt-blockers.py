#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def patch_fatal_error_relaunch(upstream_root: Path) -> None:
    """Keep desktop relaunch behavior while avoiding process creation on iOS."""

    source = upstream_root / "rpcs3/rpcs3.cpp"
    marker = "RPCS3 iOS: an app bundle cannot relaunch itself as a child process"
    text = source.read_text(encoding="utf-8")
    if marker in text:
        return

    spawn_anchor = "_wspawnl(_P_WAIT"
    spawn_pos = text.find(spawn_anchor)
    if spawn_pos < 0:
        raise SystemExit("Unable to locate upstream Windows fatal-error relaunch call")

    block_start = text.rfind("#ifdef _WIN32", 0, spawn_pos)
    if block_start < 0:
        raise SystemExit("Unable to locate the start of the fatal-error relaunch block")

    failure_anchor = 'std::fprintf(stderr, "posix_spawn() failed: %d\\n", ret);'
    failure_pos = text.find(failure_anchor, spawn_pos)
    if failure_pos < 0:
        raise SystemExit("Unable to locate upstream POSIX fatal-error relaunch call")

    block_end = text.find("#endif", failure_pos)
    if block_end < 0:
        raise SystemExit("Unable to locate the end of the fatal-error relaunch block")
    block_end += len("#endif")

    original = text[block_start:block_end]
    if not original.startswith("#ifdef _WIN32") or spawn_anchor not in original or failure_anchor not in original:
        raise SystemExit("Fatal-error relaunch anchors resolved to an unexpected source block")

    desktop_body = original[len("#ifdef _WIN32"):]
    replacement = '''#if defined(RPCS3_IOS)
		// RPCS3 iOS: an app bundle cannot relaunch itself as a child process.
		// Show the same upstream report in-process and abort through the existing path.
		show_report(text);
#elif defined(_WIN32)''' + desktop_body

    updated = text[:block_start] + replacement + text[block_end:]
    for required in (
        marker,
        "#elif defined(_WIN32)",
        spawn_anchor,
        failure_anchor,
    ):
        if required not in updated:
            raise SystemExit(f"Fatal-error relaunch patch verification failed: {required}")

    source.write_text(updated, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    patch_fatal_error_relaunch(args.upstream_root)
    print("Patched and verified the full RPCS3 Qt frontend fatal-error path for iOS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
