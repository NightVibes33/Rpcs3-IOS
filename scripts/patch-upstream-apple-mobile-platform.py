#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

MARKER = "RPCS3 Apple mobile shared platform layer"


def require(path: Path) -> str:
    if not path.is_file():
        raise SystemExit(f"Required source file is missing: {path}")
    return path.read_text(encoding="utf-8")


def write(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")


def patch_display_sleep(root: Path) -> None:
    path = root / "rpcs3/display_sleep_control.cpp"
    old = require(path)
    if MARKER in old:
        return
    if "bool display_sleep_control_supported()" not in old or "void enable_display_sleep(bool enabled)" not in old:
        raise SystemExit("Unexpected display_sleep_control.cpp shape")

    replacement = r'''#include "display_sleep_control.h"

#if defined(RPCS3_IOS)
// RPCS3 Apple mobile shared platform layer.
#include "RPCS3AppleMobilePlatform.h"
#elif defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
#include <IOKit/pwr_mgt/IOPMLib.h>
#pragma GCC diagnostic pop
static IOPMAssertionID s_pm_assertion = kIOPMNullAssertionID;
#elif defined(HAVE_QTDBUS)
#include <QtDBus/QDBusConnection>
#include <QtDBus/QDBusInterface>
#include <QtDBus/QDBusMessage>
#include <QDBusReply>
#include "util/types.hpp"
static u32 s_dbus_cookie = 0;
#endif

bool display_sleep_control_supported()
{
#if defined(RPCS3_IOS) || defined(_WIN32) || defined(__APPLE__)
    return true;
#elif defined(HAVE_QTDBUS)
    for (const char* service : { "org.freedesktop.ScreenSaver", "org.mate.ScreenSaver" })
    {
        QDBusInterface interface(service, "/ScreenSaver", service, QDBusConnection::sessionBus());
        if (interface.isValid())
        {
            return true;
        }
    }
    return false;
#else
    return false;
#endif
}

void enable_display_sleep(bool enabled)
{
    if (!display_sleep_control_supported())
    {
        return;
    }

#if defined(RPCS3_IOS)
    rpcs3_apple_mobile_set_display_sleep_enabled(enabled ? 1 : 0);
#elif defined(_WIN32)
    SetThreadExecutionState(enabled ? ES_CONTINUOUS : (ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED));
#elif defined(__APPLE__)
    if (enabled && s_pm_assertion != kIOPMNullAssertionID)
    {
        IOPMAssertionRelease(s_pm_assertion);
        s_pm_assertion = kIOPMNullAssertionID;
    }
    else if (!enabled)
    {
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wold-style-cast"
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep, kIOPMAssertionLevelOn, CFSTR("Game running"), &s_pm_assertion);
#pragma GCC diagnostic pop
    }
#elif defined(HAVE_QTDBUS)
    if (enabled && s_dbus_cookie != 0)
    {
        for (const char* service : { "org.freedesktop.ScreenSaver", "org.mate.ScreenSaver" })
        {
            QDBusInterface interface(service, "/ScreenSaver", service, QDBusConnection::sessionBus());
            if (interface.isValid())
            {
                interface.call("UnInhibit", s_dbus_cookie);
                break;
            }
        }
        s_dbus_cookie = 0;
    }
    else if (!enabled)
    {
        for (const char* service : { "org.freedesktop.ScreenSaver", "org.mate.ScreenSaver" })
        {
            QDBusInterface interface(service, "/ScreenSaver", service, QDBusConnection::sessionBus());
            if (interface.isValid())
            {
                QDBusReply<u32> reply = interface.call("Inhibit", "rpcs3", "Game running");
                if (reply.isValid())
                {
                    s_dbus_cookie = reply.value();
                }
                break;
            }
        }
    }
#endif
}
'''
    write(path, replacement)


def patch_gui_pad_thread(root: Path) -> None:
    path = root / "rpcs3/Input/gui_pad_thread.cpp"
    text = require(path)
    marker = "RPCS3 Apple mobile: desktop event injection excluded"
    if marker in text:
        return

    lines = text.splitlines()
    changed = 0
    output: list[str] = []
    for line in lines:
        stripped = line.strip()
        indent = line[: len(line) - len(line.lstrip())]
        if re.fullmatch(r"#ifdef\s+__APPLE__", stripped):
            output.append(indent + "#if defined(__APPLE__) && !defined(RPCS3_IOS)")
            changed += 1
        elif re.fullmatch(r"#if\s+defined\s*\(\s*__APPLE__\s*\)", stripped):
            output.append(indent + "#if defined(__APPLE__) && !defined(RPCS3_IOS)")
            changed += 1
        elif re.fullmatch(r"#elif\s+defined\s*\(\s*__APPLE__\s*\)", stripped):
            output.append(indent + "#elif defined(__APPLE__) && !defined(RPCS3_IOS)")
            changed += 1
        else:
            output.append(line)

    if changed == 0:
        already_guarded = "defined(__APPLE__) && !defined(RPCS3_IOS)" in text
        if not already_guarded and ("ApplicationServices/ApplicationServices.h" in text or "Carbon/Carbon.h" in text):
            raise SystemExit("Could not guard Apple desktop branches in gui_pad_thread.cpp")

    output.insert(0, "// RPCS3 Apple mobile: desktop event injection excluded; UIKit/GameController owns mobile input.")
    patched = "\n".join(output) + "\n"
    if re.search(r"^\s*#(?:if|elif)\s+defined\s*\(\s*__APPLE__\s*\)\s*$", patched, re.MULTILINE):
        raise SystemExit("An unguarded Apple desktop branch remains in gui_pad_thread.cpp")
    write(path, patched)


def patch_qt_utils(root: Path) -> None:
    path = root / "rpcs3/rpcs3qt/qt_utils.cpp"
    text = require(path)
    marker = "RPCS3 Apple mobile: use Qt/UIKit document handling"
    if marker in text:
        return

    pattern = re.compile(
        r"#elif\s+defined\(__APPLE__\)(?P<body>.*?QProcess::execute\(\"/usr/bin/osascript\".*?\n.*?)#else",
        re.DOTALL,
    )
    match = pattern.search(text)
    if not match:
        # The earlier iOS blocker patch may already have made this safe.
        if "defined(__APPLE__) && !defined(RPCS3_IOS)" in text:
            text = text.replace(
                "#elif defined(RPCS3_IOS)\n",
                "#elif defined(RPCS3_IOS)\n\t\t\t\t// RPCS3 Apple mobile: use Qt/UIKit document handling; no Finder child process.\n",
                1,
            )
            write(path, text)
            return
        raise SystemExit("Unable to find the macOS Finder/QProcess branch in qt_utils.cpp")

    body = match.group("body")
    replacement = (
        "#elif defined(__APPLE__) && !defined(RPCS3_IOS)" + body +
        "#elif defined(RPCS3_IOS)\n"
        "\t\t\t\t// RPCS3 Apple mobile: use Qt/UIKit document handling; no Finder child process.\n"
        "\t\t\t\tgui_log.notice(\"gui::utils::open_dir: mobile document path '%s'\", spath);\n"
        "#else"
    )
    write(path, text[: match.start()] + replacement + text[match.end() :])


def patch_hidapi_barrier(root: Path) -> None:
    """Enable HIDAPI's existing C pthread-barrier fallback exactly once."""

    path = root / "3rdparty/hidapi/hidapi/libusb/hidapi_thread_pthread.h"
    text = require(path)
    marker = "RPCS3 iOS: pthread barriers are unavailable on iPhoneOS"
    broken_marker = "RPCS3 Apple mobile pthread barrier compatibility"

    if broken_marker in text or "nullptr" in text:
        raise SystemExit("A duplicate C++-only HIDAPI barrier fallback is present")
    if marker in text:
        return

    needle = """#include <pthread.h>

#if defined(__ANDROID__) && __ANDROID_API__ < __ANDROID_API_N__
"""
    replacement = """#include <pthread.h>

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif

/* RPCS3 iOS: pthread barriers are unavailable on iPhoneOS. Reuse HIDAPI's
   C-compatible mutex/condition fallback that is already used on older Android. */
#if (defined(__ANDROID__) && __ANDROID_API__ < __ANDROID_API_N__) || \
    (defined(__APPLE__) && TARGET_OS_IPHONE)
"""
    if needle not in text:
        raise SystemExit("Unable to locate HIDAPI pthread barrier fallback guard")

    patched = text.replace(needle, replacement, 1)
    if patched.count(marker) != 1:
        raise SystemExit("HIDAPI iPhoneOS barrier fallback was not applied exactly once")
    if broken_marker in patched or "nullptr" in patched:
        raise SystemExit("HIDAPI barrier patch introduced a duplicate C++ fallback")
    write(path, patched)


def patch_qt_cmake(root: Path, port_root: Path) -> None:
    path = root / "rpcs3/rpcs3qt/CMakeLists.txt"
    text = require(path)
    marker = "RPCS3 Apple mobile shared target integration"
    if marker in text:
        return

    block = f'''

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # RPCS3 Apple mobile shared target integration.
    if(NOT DEFINED RPCS3_IOS_PORT_ROOT)
        set(RPCS3_IOS_PORT_ROOT "{port_root.as_posix()}")
    endif()
    include("${{RPCS3_IOS_PORT_ROOT}}/cmake/RPCS3AppleMobile.cmake")
    rpcs3_enable_apple_mobile(rpcs3_ui)
endif()
'''
    write(path, text.rstrip() + block)


def patch_vulkan_checkpoint(root: Path) -> None:
    candidates = [
        root / "rpcs3/Emu/RSX/VK/VKPresent.cpp",
        root / "pcs3/Emu/RSX/VK/swapchain.cpp",
    ]
    path = next((p for p in candidates if p.is_file()), None)
    if path is None:
        return
    text = require(path)
    marker = "RPCS3 Apple mobile first-frame checkpoint"
    if marker in text:
        return

    index = text.find("vkQueuePresentKHR")
    if index < 0:
        return
    statement_end = text.find(";kºwµç[ÊÌ¬µéš¶ë®ø¬‰¹^n‹§uªò