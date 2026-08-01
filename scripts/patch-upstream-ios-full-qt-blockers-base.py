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


def patch_qt_component_graph(upstream_root: Path) -> None:
    """Use Qt's device modules on iOS without requesting desktop QtDBus."""

    cmake = upstream_root / "3rdparty/qt6.cmake"
    marker = "RPCS3 iOS: QtDBus is a desktop-only optional component"
    text = cmake.read_text(encoding="utf-8")
    if marker in text:
        return

    old = '''add_library(3rdparty_qt6 INTERFACE)

set(QT_MIN_VER 6.7.0)

find_package(Qt6 ${QT_MIN_VER} CONFIG COMPONENTS Widgets Concurrent Multimedia MultimediaWidgets Svg SvgWidgets)
if(WIN32)
	target_link_libraries(3rdparty_qt6 INTERFACE Qt6::Widgets Qt6::Concurrent Qt6::Multimedia Qt6::MultimediaWidgets Qt6::Svg Qt6::SvgWidgets)
else()
	set(QT_NO_PRIVATE_MODULE_WARNING ON)
	find_package(Qt6 ${QT_MIN_VER} COMPONENTS DBus Gui GuiPrivate)
	if(Qt6DBus_FOUND)
		target_link_libraries(3rdparty_qt6 INTERFACE Qt6::Widgets Qt6::DBus Qt6::Concurrent Qt6::Multimedia Qt6::MultimediaWidgets Qt6::Svg Qt6::SvgWidgets)
		target_compile_definitions(3rdparty_qt6 INTERFACE -DHAVE_QTDBUS)
	else()
		target_link_libraries(3rdparty_qt6 INTERFACE Qt6::Widgets Qt6::Concurrent Qt6::Multimedia Qt6::MultimediaWidgets Qt6::Svg Qt6::SvgWidgets)
	endif()
	target_link_libraries(3rdparty_qt6 INTERFACE Qt6::GuiPrivate)
endif()
'''

    new = '''add_library(3rdparty_qt6 INTERFACE)

set(QT_MIN_VER 6.7.0)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
	# RPCS3 iOS: QtDBus is a desktop-only optional component. Resolve the
	# complete device module set in one required package lookup so CMake keeps
	# the iOS libraries paired with the host-side Qt tools.
	set(QT_NO_PRIVATE_MODULE_WARNING ON)
	find_package(Qt6 ${QT_MIN_VER} CONFIG REQUIRED COMPONENTS
		Widgets Concurrent Multimedia MultimediaWidgets Svg SvgWidgets Gui GuiPrivate)
	target_link_libraries(3rdparty_qt6 INTERFACE
		Qt6::Widgets Qt6::Concurrent Qt6::Multimedia Qt6::MultimediaWidgets
		Qt6::Svg Qt6::SvgWidgets Qt6::GuiPrivate)
else()
	find_package(Qt6 ${QT_MIN_VER} CONFIG COMPONENTS Widgets Concurrent Multimedia MultimediaWidgets Svg SvgWidgets)
	if(WIN32)
		target_link_libraries(3rdparty_qt6 INTERFACE Qt6::Widgets Qt6::Concurrent Qt6::Multimedia Qt6::MultimediaWidgets Qt6::Svg Qt6::SvgWidgets)
	else()
		set(QT_NO_PRIVATE_MODULE_WARNING ON)
		find_package(Qt6 ${QT_MIN_VER} COMPONENTS DBus Gui GuiPrivate)
		if(Qt6DBus_FOUND)
			target_link_libraries(3rdparty_qt6 INTERFACE Qt6::Widgets Qt6::DBus Qt6::Concurrent Qt6::Multimedia Qt6::MultimediaWidgets Qt6::Svg Qt6::SvgWidgets)
			target_compile_definitions(3rdparty_qt6 INTERFACE -DHAVE_QTDBUS)
		else()
			target_link_libraries(3rdparty_qt6 INTERFACE Qt6::Widgets Qt6::Concurrent Qt6::Multimedia Qt6::MultimediaWidgets Qt6::Svg Qt6::SvgWidgets)
		endif()
		target_link_libraries(3rdparty_qt6 INTERFACE Qt6::GuiPrivate)
	endif()
endif()
'''

    if old not in text:
        raise SystemExit("Unable to locate the pinned RPCS3 Qt component block")
    updated = text.replace(old, new, 1)
    for required in (
        marker,
        'CMAKE_SYSTEM_NAME STREQUAL "iOS"',
        "CONFIG REQUIRED COMPONENTS",
        "Qt6::GuiPrivate",
    ):
        if required not in updated:
            raise SystemExit(f"Qt iOS component patch verification failed: {required}")
    cmake.write_text(updated, encoding="utf-8")


def patch_qt_utils_process_launch(upstream_root: Path) -> None:
    """Keep Finder reveal support on macOS while avoiding QProcess on iOS."""

    source = upstream_root / "rpcs3/rpcs3qt/qt_utils.cpp"
    marker = "RPCS3 iOS: Finder reveal and child processes are unavailable"
    text = source.read_text(encoding="utf-8")
    if marker in text:
        return

    old = '''#elif defined(__APPLE__)
				gui_log.notice("gui::utils::open_dir: About to open file path '%s'", spath);

				QProcess::execute("/usr/bin/osascript", { "-e", "tell application \\"Finder\\" to reveal POSIX file \\"" + path + "\\"" });
				QProcess::execute("/usr/bin/osascript", { "-e", "tell application \\"Finder\\" to activate" });
#else
'''
    new = '''#elif defined(__APPLE__) && !defined(RPCS3_IOS)
				gui_log.notice("gui::utils::open_dir: About to open file path '%s'", spath);

				QProcess::execute("/usr/bin/osascript", { "-e", "tell application \\"Finder\\" to reveal POSIX file \\"" + path + "\\"" });
				QProcess::execute("/usr/bin/osascript", { "-e", "tell application \\"Finder\\" to activate" });
#elif defined(RPCS3_IOS)
				// RPCS3 iOS: Finder reveal and child processes are unavailable.
				// The caller already has the sandbox path, so leave it unchanged.
				gui_log.notice("gui::utils::open_dir: Finder reveal is unavailable on iOS for '%s'", spath);
#else
'''
    if old not in text:
        raise SystemExit("Unable to locate the pinned Qt Finder reveal branch")

    updated = text.replace(old, new, 1)
    for required in (
        marker,
        "#elif defined(__APPLE__) && !defined(RPCS3_IOS)",
        "#elif defined(RPCS3_IOS)",
        'QProcess::execute("/usr/bin/osascript"',
    ):
        if required not in updated:
            raise SystemExit(f"Qt process-launch patch verification failed: {required}")

    source.write_text(updated, encoding="utf-8")


def patch_gui_pad_thread_desktop_events(upstream_root: Path) -> None:
    """Exclude macOS CoreGraphics/Carbon event injection from the iOS frontend."""

    source = upstream_root / "rpcs3/Input/gui_pad_thread.cpp"
    marker = "RPCS3 iOS: desktop CoreGraphics input injection is unavailable"
    text = source.read_text(encoding="utf-8")
    if marker in text:
        return

    normal_guard = "#elif defined(__APPLE__)"
    spaced_guard = "#elif defined (__APPLE__)"
    if text.count(normal_guard) != 5 or text.count(spaced_guard) != 1:
        raise SystemExit("Unexpected Apple desktop event guards in gui_pad_thread.cpp")

    ios_safe_guard = "#elif defined(__APPLE__) && !defined(RPCS3_IOS)"
    updated = text.replace(normal_guard, ios_safe_guard)
    updated = updated.replace(spaced_guard, ios_safe_guard)
    updated = updated.replace(
        ios_safe_guard + "\n",
        ios_safe_guard + "\n// RPCS3 iOS: desktop CoreGraphics input injection is unavailable.\n",
        1,
    )

    if marker not in updated:
        raise SystemExit("Qt GUI pad desktop-event marker was not inserted")
    if updated.count(ios_safe_guard) != 6:
        raise SystemExit("Qt GUI pad patch did not guard every Apple desktop branch")
    if "\n#elif defined(__APPLE__)\n" in updated or "\n#elif defined (__APPLE__)\n" in updated:
        raise SystemExit("Qt GUI pad patch left an unguarded Apple desktop branch")

    source.write_text(updated, encoding="utf-8")


def patch_display_sleep_control(upstream_root: Path) -> None:
    """Keep the macOS IOPM backend off iOS, where UIKit owns app sleep behavior."""

    source = upstream_root / "rpcs3/display_sleep_control.cpp"
    marker = "RPCS3 iOS: display sleep control is managed by UIKit"
    text = source.read_text(encoding="utf-8")
    if marker in text:
        return

    apple_guard = "#elif defined(__APPLE__)"
    if text.count(apple_guard) != 2:
        raise SystemExit("Unexpected Apple display-sleep guard count")

    ios_safe_guard = "#elif defined(__APPLE__) && !defined(RPCS3_IOS)"
    updated = text.replace(apple_guard, ios_safe_guard)
    updated = updated.replace(
        ios_safe_guard + "\n#pragma GCC diagnostic push",
        ios_safe_guard + "\n// RPCS3 iOS: display sleep control is managed by UIKit.\n#pragma GCC diagnostic push",
        1,
    )

    supported = "#if defined(_WIN32) || defined(__APPLE__)"
    supported_ios_safe = "#if defined(_WIN32) || (defined(__APPLE__) && !defined(RPCS3_IOS))"
    if updated.count(supported) != 1:
        raise SystemExit("Unable to locate display sleep support condition")
    updated = updated.replace(supported, supported_ios_safe, 1)

    for required in (
        marker,
        "#include <IOKit/pwr_mgt/IOPMLib.h>",
        supported_ios_safe,
    ):
        if required not in updated:
            raise SystemExit(f"Display sleep patch verification failed: {required}")
    if updated.count(ios_safe_guard) != 2:
        raise SystemExit("Display sleep patch did not guard both macOS branches")

    source.write_text(updated, encoding="utf-8")


def patch_no_exception_noreturn_paths(upstream_root: Path) -> None:
    """Preserve fatal-path control flow when iOS builds without C++ exceptions."""

    compiler = upstream_root / "buildfiles/cmake/ConfigureCompiler.cmake"
    compiler_text = compiler.read_text(encoding="utf-8")
    strict_return = "\tadd_compile_options(-Werror=return-type)"
    ios_return = """\tif(RPCS3_IOS_UPSTREAM_GRAPH)
\t\t# Clang 26 does not consistently propagate noreturn from RPCS3 fatal constructors.
\t\tadd_compile_options(-Wreturn-type)
\telse()
\t\tadd_compile_options(-Werror=return-type)
\tendif()"""
    if ios_return not in compiler_text:
        if compiler_text.count(strict_return) != 1:
            raise SystemExit("Unable to locate upstream return-type diagnostic")
        compiler_text = compiler_text.replace(strict_return, ios_return, 1)

    strict_fallthrough = "\tadd_compile_options(-Werror=implicit-fallthrough)"
    ios_fallthrough = """\tif(RPCS3_IOS_UPSTREAM_GRAPH)
\t\tadd_compile_options(-Wimplicit-fallthrough)
\telse()
\t\tadd_compile_options(-Werror=implicit-fallthrough)
\tendif()"""
    if ios_fallthrough not in compiler_text:
        if compiler_text.count(strict_fallthrough) != 1:
            raise SystemExit("Unable to locate upstream fallthrough diagnostic")
        compiler_text = compiler_text.replace(strict_fallthrough, ios_fallthrough, 1)

    compiler.write_text(compiler_text, encoding="utf-8")

    replacements = (
        (
            upstream_root / "rpcs3/Emu/Cell/SPUThread.h",
            '\t\t\tfmt::throw_exception("Unexpected slice value (%d)", slice);\n',
            '\t\t\tfmt::throw_exception("Unexpected slice value (%d)", slice);\n\t\t\t__builtin_unreachable();\n',
        ),
        (
            upstream_root / "rpcs3/Emu/Memory/vm.cpp",
            '\tfmt::throw_exception("Failed to reserve vm memory");\n',
            '\tfmt::throw_exception("Failed to reserve vm memory");\n\t__builtin_unreachable();\n',
        ),
        (
            upstream_root / "rpcs3/Crypto/utils.cpp",
            '\t\tfmt::throw_exception("vtrm_get_laid_paid_from_type: Wrong type specified (type=%d)", type);\n',
            '\t\tfmt::throw_exception("vtrm_get_laid_paid_from_type: Wrong type specified (type=%d)", type);\n\t\t__builtin_unreachable();\n',
        ),
        (
            upstream_root / "rpcs3/Crypto/utils.cpp",
            '\t\tfmt::throw_exception("vtrm_portability_type_mapper: Wrong type specified (type=%d)", type);\n',
            '\t\tfmt::throw_exception("vtrm_portability_type_mapper: Wrong type specified (type=%d)", type);\n\t\t__builtin_unreachable();\n',
        ),
        (
            upstream_root / "rpcs3/Emu/Io/MouseHandler.h",
            '\tdefault: fmt::throw_exception("get_mouse_button_code: Invalid index %d", i);\n',
            '\tdefault: fmt::throw_exception("get_mouse_button_code: Invalid index %d", i);\n\t\t__builtin_unreachable();\n',
        ),
    )
    for source, old, new in replacements:
        text = source.read_text(encoding="utf-8")
        if new in text:
            continue
        if text.count(old) != 1:
            raise SystemExit(f"Unable to locate no-exception fatal path in {source}")
        source.write_text(text.replace(old, new, 1), encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    patch_fatal_error_relaunch(args.upstream_root)
    patch_qt_component_graph(args.upstream_root)
    patch_qt_utils_process_launch(args.upstream_root)
    patch_gui_pad_thread_desktop_events(args.upstream_root)
    patch_display_sleep_control(args.upstream_root)
    patch_no_exception_noreturn_paths(args.upstream_root)
    print("Patched and verified the full RPCS3 Qt frontend fatal-error, component, process-launch, desktop input, and display-sleep paths for iOS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
