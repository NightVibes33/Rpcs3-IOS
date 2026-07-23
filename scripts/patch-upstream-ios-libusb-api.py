#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1])
source = root / "3rdparty/libusb/libusb/libusb/os/ios_usb.c"
text = source.read_text(encoding="utf-8")
text = text.replace(
    "static void ios_exit(void) {}",
    "static void ios_exit(struct libusb_context *ctx) { (void)ctx; }",
)
text = text.replace(
    "static int ios_clock_gettime(int clkid, struct timespec *tp)\n{ return clock_gettime(clkid, tp); }\n\n",
    "",
)
text = text.replace("    .clock_gettime = ios_clock_gettime,\n", "")

marker = "/* RPCS3_IOS_LIBUSB_CLOCKS */"
if marker not in text:
    text += f'''\n\n{marker}\nint usbi_get_monotonic_time(struct timespec *tp)\n{{\n    return clock_gettime(CLOCK_MONOTONIC, tp);\n}}\n\nint usbi_get_real_time(struct timespec *tp)\n{{\n    return clock_gettime(CLOCK_REALTIME, tp);\n}}\n'''

for required in (
    "static void ios_exit(struct libusb_context *ctx)",
    "int usbi_get_monotonic_time(struct timespec *tp)",
    "int usbi_get_real_time(struct timespec *tp)",
):
    if required not in text:
        raise SystemExit(f"iOS libusb patch verification failed: {required}")

source.write_text(text, encoding="utf-8")
print(f"Patched iOS libusb backend API and POSIX clocks in {source}")
