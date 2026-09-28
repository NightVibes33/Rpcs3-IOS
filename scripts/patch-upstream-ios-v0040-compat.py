#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def replace_or_verify(text: str, old: str, new: str, label: str) -> str:
    if old in text:
        return text.replace(old, new, 1)
    if new in text:
        return text
    raise SystemExit(f"Unable to locate {label}")


def patch_runtime_bridge(port_root: Path) -> None:
    path = port_root / "CoreBridge/RPCS3UpstreamRuntimeBridge.cpp"
    text = path.read_text(encoding="utf-8")

    text = replace_or_verify(
        text,
        "    g_cfg.video.vk.adapter.set(adapter);\n",
        "    g_cfg.video.vk.adapter.from_string(adapter);\n",
        "v0.0.40 Vulkan adapter assignment",
    )
    text = replace_or_verify(
        text,
        "    g_cfg.video.vk.adapter.set(std::string{k_ios_vulkan_adapter});\n",
        "    g_cfg.video.vk.adapter.from_string(k_ios_vulkan_adapter);\n",
        "v0.0.40 persisted Vulkan adapter assignment",
    )
    text = replace_or_verify(
        text,
        "    Emu.SetSupportedRenderers(std::set<video_renderer>{video_renderer::null, video_renderer::vulkan});\n",
        "    // v0.0.40 selects the default renderer directly; it has no supported-renderer list API.\n",
        "v0.0.40 Vulkan supported-renderer call",
    )
    text = replace_or_verify(
        text,
        "    Emu.SetSupportedRenderers(std::set<video_renderer>{video_renderer::null});\n",
        "    // v0.0.40 selects Null as the default renderer directly.\n",
        "v0.0.40 Null supported-renderer call",
    )
    text = replace_or_verify(
        text,
        "    callbacks.get_database_config = [](const std::string&) -> std::string { return {}; };\n",
        "    // Database-config callbacks were added after the pinned v0.0.40 ABI.\n",
        "v0.0.40 database-config callback",
    )
    text = replace_or_verify(
        text,
        "        Emu.SetHeadless(false);\n",
        "        // v0.0.40 has no SetHeadless API; SetHasGui(false) owns this host mode.\n",
        "v0.0.40 headless setter",
    )

    path.write_text(text, encoding="utf-8")


def patch_firmware_installer(port_root: Path) -> None:
    path = port_root / "CoreBridge/RPCS3UpstreamFirmwareInstaller.cpp"
    text = path.read_text(encoding="utf-8")

    text = text.replace("#include <exception>\n", "", 1)

    old_reinitialize = '''bool reinitialize_after_firmware_mount()
{
    try
    {
        // This mirrors upstream main_window::HandlePupInstallation. Emu.Init()
        // rebuilds the VFS mounts after the temporary /dev_flash extraction mount.
        Emu.Init();
        return true;
    }
    catch (...)
    {
        return false;
    }
}
'''
    new_reinitialize = '''bool reinitialize_after_firmware_mount()
{
    // This mirrors upstream main_window::HandlePupInstallation. Emu.Init()
    // rebuilds the VFS mounts after the temporary /dev_flash extraction mount.
    // RPCS3 v0.0.40 is compiled with -fno-exceptions, so failure is reported by
    // the upstream state/logging path rather than a C++ exception handler.
    Emu.Init();
    return true;
}
'''
    text = replace_or_verify(
        text,
        old_reinitialize,
        new_reinitialize,
        "no-exceptions firmware reinitialization block",
    )

    old_try = "    try\n    {\n"
    new_try = "    {\n"
    text = replace_or_verify(
        text,
        old_try,
        new_try,
        "no-exceptions firmware installation block",
    )

    old_catches = '''    catch (const std::exception& error)
    {
        if (flash_mounted)
            reinitialize_after_firmware_mount();
        set_firmware_failure(std::string("RPCS3 firmware installation failed: ") + error.what());
        return 0;
    }
    catch (...)
    {
        if (flash_mounted)
            reinitialize_after_firmware_mount();
        set_firmware_failure("RPCS3 firmware installation failed with an unknown exception.");
        return 0;
    }
'''
    catch_marker = "    // RPCS3 v0.0.40 firmware installer uses the upstream no-exceptions error path.\n"
    text = replace_or_verify(
        text,
        old_catches,
        catch_marker,
        "firmware exception handlers",
    )

    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("port_root", type=Path, nargs="?", default=Path.cwd())
    args = parser.parse_args()
    port_root = args.port_root.resolve()

    patch_runtime_bridge(port_root)
    patch_firmware_installer(port_root)

    print("Patched port runtime sources for the pinned RPCS3 v0.0.40 no-exceptions API")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
