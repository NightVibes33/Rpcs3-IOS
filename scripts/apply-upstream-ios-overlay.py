#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

MARKER = "# BEGIN RPCS3-IOS OVERLAY"


def block(mode: str) -> str:
    if mode == "bootstrap":
        body = '''option(RPCS3_IOS_CORE_ONLY "Build only the RPCS3 iOS bootstrap static core" OFF)
if(RPCS3_IOS_CORE_ONLY)
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
        message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point to the iOS port repository")
    endif()
    add_compile_definitions(
        RPCS3_IOS=1
        RPCS3_PLATFORM_MOBILE=1
        RPCS3_PLATFORM_DESKTOP=0
    )
    add_subdirectory(
        "${RPCS3_IOS_PORT_ROOT}/Port"
        "${CMAKE_BINARY_DIR}/rpcs3-ios-port"
    )
    return()
endif()
'''
    else:
        body = '''option(RPCS3_IOS_UPSTREAM_GRAPH "Configure RPCS3's real upstream build graph for iOS" OFF)
if(RPCS3_IOS_UPSTREAM_GRAPH)
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
        message(FATAL_ERROR "RPCS3_IOS_PORT_ROOT must point to the iOS port repository")
    endif()
    add_compile_definitions(
        RPCS3_IOS=1
        RPCS3_PLATFORM_MOBILE=1
        RPCS3_PLATFORM_DESKTOP=0
    )
    set(USE_FAUDIO OFF CACHE BOOL "" FORCE)
    set(USE_NATIVE_INSTRUCTIONS OFF CACHE BOOL "" FORCE)
    set(USE_PRECOMPILED_HEADERS OFF CACHE BOOL "" FORCE)
    set(BUILD_LLVM_SUBMODULE OFF CACHE BOOL "" FORCE)
    message(STATUS "RPCS3 iOS: entering the real upstream dependency and emulator graph")
endif()
'''
    return f"{MARKER}\n{body}# END RPCS3-IOS OVERLAY\n"


def patch_libusb_for_ios(upstream_root: Path) -> None:
    cmake = upstream_root / "3rdparty/libusb/os.cmake"
    text = cmake.read_text(encoding="utf-8")
    needle = '''\tif (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
\t\tset(PLATFORM_SRC
\t\t\tdarwin_usb.c
\t\t\tthreads_posix.c
\t\t\tevents_posix.c
\t\t)

\t\tfind_package(IOKit REQUIRED)
'''
    replacement = '''\tif (CMAKE_SYSTEM_NAME STREQUAL "iOS")
\t\t# iOS does not expose desktop IOKit USB host APIs to applications.
\t\t# Keep libusb's POSIX event/thread core in the graph while compiling a
\t\t# port-owned backend that reports no host USB devices.
\t\tset(PLATFORM_SRC
\t\t\tios_usb.c
\t\t\tthreads_posix.c
\t\t\tevents_posix.c
\t\t)
\telseif (CMAKE_SYSTEM_NAME STREQUAL "Darwin")
\t\tset(PLATFORM_SRC
\t\t\tdarwin_usb.c
\t\t\tthreads_posix.c
\t\t\tevents_posix.c
\t\t)

\t\tfind_package(IOKit REQUIRED)
'''
    if needle not in text:
        raise SystemExit("Unable to locate upstream libusb Darwin platform block")
    cmake.write_text(text.replace(needle, replacement, 1), encoding="utf-8")

    source = upstream_root / "3rdparty/libusb/libusb/libusb/os/ios_usb.c"
    source.write_text('''/* RPCS3 iOS libusb backend: iOS apps cannot access desktop USB host APIs. */
#include "libusbi.h"

static int ios_init(struct libusb_context *ctx) { (void)ctx; return LIBUSB_SUCCESS; }
static void ios_exit(void) {}
static int ios_get_device_list(struct libusb_context *ctx, struct discovered_devs **discdevs)
{
    (void)ctx; (void)discdevs; return LIBUSB_SUCCESS;
}
static int ios_open(struct libusb_device_handle *handle) { (void)handle; return LIBUSB_ERROR_NOT_SUPPORTED; }
static void ios_close(struct libusb_device_handle *handle) { (void)handle; }
static int ios_get_active_config_descriptor(struct libusb_device *device, void *buffer, size_t len)
{ (void)device; (void)buffer; (void)len; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_get_config_descriptor(struct libusb_device *device, uint8_t config_index, void *buffer, size_t len)
{ (void)device; (void)config_index; (void)buffer; (void)len; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_get_configuration(struct libusb_device_handle *handle, uint8_t *config)
{ (void)handle; (void)config; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_set_configuration(struct libusb_device_handle *handle, int config)
{ (void)handle; (void)config; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_claim_interface(struct libusb_device_handle *handle, uint8_t interface_number)
{ (void)handle; (void)interface_number; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_release_interface(struct libusb_device_handle *handle, uint8_t interface_number)
{ (void)handle; (void)interface_number; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_set_interface_altsetting(struct libusb_device_handle *handle, uint8_t interface_number, uint8_t altsetting)
{ (void)handle; (void)interface_number; (void)altsetting; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_clear_halt(struct libusb_device_handle *handle, unsigned char endpoint)
{ (void)handle; (void)endpoint; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_reset_device(struct libusb_device_handle *handle)
{ (void)handle; return LIBUSB_ERROR_NOT_SUPPORTED; }
static void ios_destroy_device(struct libusb_device *device) { (void)device; }
static int ios_submit_transfer(struct usbi_transfer *itransfer)
{ (void)itransfer; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_cancel_transfer(struct usbi_transfer *itransfer)
{ (void)itransfer; return LIBUSB_ERROR_NOT_SUPPORTED; }
static void ios_clear_transfer_priv(struct usbi_transfer *itransfer) { (void)itransfer; }
static int ios_handle_events(struct libusb_context *ctx, void *event_data, unsigned int count, unsigned int num_ready)
{ (void)ctx; (void)event_data; (void)count; (void)num_ready; return LIBUSB_SUCCESS; }
static int ios_handle_transfer_completion(struct usbi_transfer *itransfer)
{ (void)itransfer; return LIBUSB_ERROR_NOT_SUPPORTED; }
static int ios_clock_gettime(int clkid, struct timespec *tp)
{ return clock_gettime(clkid, tp); }

const struct usbi_os_backend usbi_backend = {
    .name = "iOS no-host-USB backend",
    .caps = 0,
    .init = ios_init,
    .exit = ios_exit,
    .get_device_list = ios_get_device_list,
    .open = ios_open,
    .close = ios_close,
    .get_active_config_descriptor = ios_get_active_config_descriptor,
    .get_config_descriptor = ios_get_config_descriptor,
    .get_configuration = ios_get_configuration,
    .set_configuration = ios_set_configuration,
    .claim_interface = ios_claim_interface,
    .release_interface = ios_release_interface,
    .set_interface_altsetting = ios_set_interface_altsetting,
    .clear_halt = ios_clear_halt,
    .reset_device = ios_reset_device,
    .destroy_device = ios_destroy_device,
    .submit_transfer = ios_submit_transfer,
    .cancel_transfer = ios_cancel_transfer,
    .clear_transfer_priv = ios_clear_transfer_priv,
    .handle_events = ios_handle_events,
    .handle_transfer_completion = ios_handle_transfer_completion,
    .clock_gettime = ios_clock_gettime,
    .device_priv_size = 0,
    .device_handle_priv_size = 0,
    .transfer_priv_size = 0,
};
''', encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("--mode", choices=("bootstrap", "upstream"), default="bootstrap")
    args = parser.parse_args()

    cmake = args.upstream_root / "CMakeLists.txt"
    text = cmake.read_text(encoding="utf-8")
    if MARKER not in text:
        needle = "project(rpcs3 LANGUAGES C CXX)\n"
        if needle not in text:
            raise SystemExit("Unable to locate the upstream RPCS3 project declaration")
        cmake.write_text(text.replace(needle, needle + "\n" + block(args.mode), 1), encoding="utf-8")

    if args.mode == "upstream":
        patch_libusb_for_ios(args.upstream_root)

    print(f"Applied {args.mode} iOS overlay to {cmake}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
