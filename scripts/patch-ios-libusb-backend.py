#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Match the generated iOS libusb backend to RPCS3's pinned libusb ABI")
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    source = args.upstream_root / "3rdparty/libusb/libusb/libusb/os/ios_usb.c"
    text = source.read_text(encoding="utf-8")

    old_exit = "static void ios_exit(void) {}"
    new_exit = "static void ios_exit(struct libusb_context *ctx) { (void)ctx; }"
    if old_exit in text:
        text = text.replace(old_exit, new_exit, 1)
    elif new_exit not in text:
        raise SystemExit("Unable to locate the generated iOS libusb exit callback")

    clock_function = """static int ios_clock_gettime(int clkid, struct timespec *tp)
{ return clock_gettime(clkid, tp); }

"""
    text = text.replace(clock_function, "")
    text = text.replace("    .clock_gettime = ios_clock_gettime,\n", "")

    if ".clock_gettime" in text:
        raise SystemExit("The iOS libusb backend still initializes an unsupported clock_gettime field")
    if new_exit not in text:
        raise SystemExit("The iOS libusb exit callback still has the wrong ABI")

    source.write_text(text, encoding="utf-8")
    print(f"Patched pinned libusb ABI in {source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
