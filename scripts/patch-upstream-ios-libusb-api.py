#!/usr/bin/env python3
from pathlib import Path
import re
import sys

# Keep generated definitions synchronized with the pinned libusb declarations.
root = Path(sys.argv[1])
source = root / "3rdparty/libusb/libusb/libusb/os/ios_usb.c"
header = root / "3rdparty/libusb/libusb/libusb/libusbi.h"
text = source.read_text(encoding="utf-8")
header_text = header.read_text(encoding="utf-8")

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
marker_index = text.find(marker)
if marker_index >= 0:
    text = text[:marker_index].rstrip()


def declared_return_type(name: str) -> str:
    match = re.search(
        rf"(?m)^\s*(void|int)\s+{re.escape(name)}\s*\(\s*struct timespec\s*\*\s*tp\s*\)\s*;",
        header_text,
    )
    if not match:
        raise SystemExit(f"Could not find the upstream declaration for {name}")
    return match.group(1)


def clock_definition(name: str, clock_id: str) -> str:
    return_type = declared_return_type(name)
    if return_type == "void":
        statement = f"    (void)clock_gettime({clock_id}, tp);"
    else:
        statement = f"    return clock_gettime({clock_id}, tp);"
    return f"{return_type} {name}(struct timespec *tp)\n{{\n{statement}\n}}"


definitions = [
    clock_definition("usbi_get_monotonic_time", "CLOCK_MONOTONIC"),
    clock_definition("usbi_get_real_time", "CLOCK_REALTIME"),
]
text += f"\n\n{marker}\n" + "\n\n".join(definitions) + "\n"

for name in ("usbi_get_monotonic_time", "usbi_get_real_time"):
    return_type = declared_return_type(name)
    required = f"{return_type} {name}(struct timespec *tp)"
    if required not in text:
        raise SystemExit(f"iOS libusb patch verification failed: {required}")

required_exit = "static void ios_exit(struct libusb_context *ctx)"
if required_exit not in text:
    raise SystemExit(f"iOS libusb patch verification failed: {required_exit}")

source.write_text(text, encoding="utf-8")
print(f"Patched iOS libusb backend API and POSIX clocks in {source}")
