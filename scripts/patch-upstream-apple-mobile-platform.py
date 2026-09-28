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
    path = root / "3rdparty/hidapi/hidapi/libusb/hidapi_thread_pthread.h"
    text = require(path)
    marker = "RPCS3 Apple mobile pthread barrier compatibility"
    if marker in text:
        return

    include_anchor = "#include <pthread.h>"
    if include_anchor not in text:
        raise SystemExit("Unable to locate pthread include in HIDAPI thread header")

    fallback = r'''

#if defined(__APPLE__)
// RPCS3 Apple mobile pthread barrier compatibility. Darwin does not expose
// pthread_barrier_t, including on both iOS and iPadOS.
#ifndef PTHREAD_BARRIER_SERIAL_THREAD
#define PTHREAD_BARRIER_SERIAL_THREAD 1

typedef struct
{
    pthread_mutex_t mutex;
    pthread_cond_t condition;
    unsigned threshold;
    unsigned waiting;
    unsigned generation;
} pthread_barrier_t;

static inline int pthread_barrier_init(pthread_barrier_t* barrier, const void*, unsigned count)
{
    if (!barrier || count == 0) return EINVAL;
    int result = pthread_mutex_init(&barrier->mutex, nullptr);
    if (result != 0) return result;
    result = pthread_cond_init(&barrier->condition, nullptr);
    if (result != 0)
    {
        pthread_mutex_destroy(&barrier->mutex);
        return result;
    }
    barrier->threshold = count;
    barrier->waiting = 0;
    barrier->generation = 0;
    return 0;
}

static inline int pthread_barrier_destroy(pthread_barrier_t* barrier)
{
    if (!barrier) return EINVAL;
    int result = pthread_cond_destroy(&barrier->condition);
    const int mutex_result = pthread_mutex_destroy(&barrier->mutex);
    return result != 0 ? result : mutex_result;
}

static inline int pthread_barrier_wait(pthread_barrier_t* barrier)
{
    if (!barrier) return EINVAL;
    pthread_mutex_lock(&barrier->mutex);
    const unsigned generation = barrier->generation;
    if (++barrier->waiting == barrier->threshold)
    {
        barrier->waiting = 0;
        ++barrier->generation;
        pthread_cond_broadcast(&barrier->condition);
        pthread_mutex_unlock(&barrier->mutex);
        return PTHREAD_BARRIER_SERIAL_THREAD;
    }
    while (generation == barrier->generation)
    {
        pthread_cond_wait(&barrier->condition, &barrier->mutex);
    }
    pthread_mutex_unlock(&barrier->mutex);
    return 0;
}
#endif
#endif
'''
    if "#include <errno.h>" not in text:
        text = text.replace(include_anchor, "#include <errno.h>\n" + include_anchor, 1)
    text = text.replace(include_anchor, include_anchor + fallback, 1)
    write(path, text)


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
        root / "rpcs3/Emu/RSX/VK/swapchain.cpp",
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
    statement_end = text.find(";", index)
    if statement_end < 0:
        return

    include = '#if defined(RPCS3_IOS)\n#include "RPCS3AppleMobilePlatform.h"\n#endif\n'
    first_include = text.find("#include")
    if first_include >= 0 and "RPCS3AppleMobilePlatform.h" not in text:
        text = text[:first_include] + include + text[first_include:]
        index = text.find("vkQueuePresentKHR")
        statement_end = text.find(";", index)

    insertion = (
        "\n#if defined(RPCS3_IOS)\n"
        "    // RPCS3 Apple mobile first-frame checkpoint. Reaching this point means\n"
        "    // the Vulkan/MoltenVK presentation call returned to RPCS3.\n"
        "    rpcs3_apple_mobile_mark_frame_presented();\n"
        "#endif"
    )
    text = text[: statement_end + 1] + insertion + text[statement_end + 1 :]
    write(path, text)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    parser.add_argument("--port-root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()

    root = args.upstream_root.resolve()
    port_root = args.port_root.resolve()
    if not (port_root / "CoreBridge/RPCS3AppleMobilePlatform.mm").is_file():
        raise SystemExit(f"Apple mobile bridge missing under port root: {port_root}")

    patch_display_sleep(root)
    patch_gui_pad_thread(root)
    patch_qt_utils(root)
    patch_hidapi_barrier(root)
    patch_qt_cmake(root, port_root)
    patch_vulkan_checkpoint(root)
    print("Patched upstream RPCS3 for the shared iOS/iPadOS platform layer")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
