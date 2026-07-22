#include "RPCS3CoreBridge.h"
#include "RPCS3UpstreamRuntimeHost.h"
#include "IOSFilesystem.h"
#include "IOSPlatform.h"

#include "Emu/System.h"
#include "Emu/system_utils.hpp"

#include <filesystem>
#include <mutex>
#include <string>
#include <utility>

namespace
{
std::mutex g_mutex;
bool g_platform_initialized = false;
bool g_runtime_linked = false;
bool g_callbacks_initialized = false;
bool g_ppu_interpreter = false;
bool g_spu_interpreter = false;
bool g_jit = false;
bool g_renderer = false;
rpcs3::ios::filesystem_layout g_layout;
std::string g_message = "RPCS3 upstream execution host has not been initialized.";
std::string g_last_boot_path;

void set_message(std::string message)
{
    g_message = std::move(message);
}

RPCS3IOSRendererBackend public_renderer(rpcs3::ios::upstream::renderer_backend renderer)
{
    return renderer == rpcs3::ios::upstream::renderer_backend::metal
        ? RPCS3IOSRendererMetal
        : RPCS3IOSRendererVulkan;
}

rpcs3::ios::upstream::renderer_backend upstream_renderer(RPCS3IOSRendererBackend renderer)
{
    return renderer == RPCS3IOSRendererMetal
        ? rpcs3::ios::upstream::renderer_backend::metal
        : rpcs3::ios::upstream::renderer_backend::vulkan;
}

RPCS3IOSCoreState current_state()
{
    if (!g_platform_initialized || !g_runtime_linked)
        return RPCS3IOSCoreStateUnavailable;
    if (Emu.IsRunning())
        return RPCS3IOSCoreStateRunning;
    if (Emu.IsPausedOrReady())
        return RPCS3IOSCoreStateReady;
    if (Emu.IsStopped())
        return RPCS3IOSCoreStateStopped;
    return RPCS3IOSCoreStateReady;
}

bool valid_sandbox_path(const char* path)
{
    return path && *path && rpcs3::ios::path_is_within_app_container(path) &&
           std::filesystem::exists(path);
}

int boot_result(game_boot_result result, const char* operation)
{
    if (is_error(result))
    {
        set_message(std::string(operation) + " failed with RPCS3 game_boot_result " +
                    std::to_string(static_cast<unsigned>(result)) + ".");
        return 0;
    }
    set_message(std::string(operation) + " was accepted by RPCS3 Emu.System.");
    return 1;
}
} // namespace

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void)
{
    thread_local std::string message_copy;
    thread_local std::string path_copy;

    std::lock_guard lock(g_mutex);
    message_copy = g_message;
    path_copy = g_layout.root;

    RPCS3IOSCoreDiagnostics result = {};
    result.state = current_state();
    result.capability_level = g_runtime_linked
        ? RPCS3IOSCoreCapabilityExecutionCapable
        : RPCS3IOSCoreCapabilityPartialUpstream;
    result.platform_initialized = g_platform_initialized ? 1 : 0;
    result.upstream_crypto_available = 1;
    result.upstream_source_count = g_runtime_linked ? 1 : 0;
    result.ppu_interpreter_available = g_ppu_interpreter ? 1 : 0;
    result.spu_interpreter_available = g_spu_interpreter ? 1 : 0;
    result.jit_available = g_jit ? 1 : 0;
    result.renderer_available = g_renderer ? 1 : 0;
    result.upstream_runtime_linked = g_runtime_linked ? 1 : 0;
    result.host_callbacks_initialized = g_callbacks_initialized ? 1 : 0;
    result.selected_renderer = public_renderer(rpcs3::ios::upstream::selected_renderer());
    result.upstream_revision = "v0.0.40";
    result.build_classification = g_runtime_linked
        ? "upstream-execution-interpreter"
        : "partial-upstream";
    result.data_path = path_copy.empty() ? nullptr : path_copy.c_str();
    result.last_boot_sha256 = nullptr;
    result.message = message_copy.c_str();
    return result;
}

int rpcs3_ios_core_initialize(const char* data_path)
{
    std::lock_guard lock(g_mutex);
    g_layout = rpcs3::ios::prepare_filesystem_layout(data_path);
    if (!g_layout.ready)
    {
        g_platform_initialized = false;
        g_runtime_linked = false;
        set_message(g_layout.error.empty() ? "Unable to prepare the RPCS3 sandbox." : g_layout.error);
        return 0;
    }

    const rpcs3::ios::platform_capabilities capabilities = rpcs3::ios::query_platform_capabilities();
    if (!capabilities.physical_device)
    {
        g_platform_initialized = false;
        g_runtime_linked = false;
        set_message("RPCS3 iOS execution requires a physical arm64 iOS device.");
        return 0;
    }

    const rpcs3::ios::upstream::runtime_host_status host =
        rpcs3::ios::upstream::initialize_runtime_host(g_layout);
    g_platform_initialized = true;
    g_runtime_linked = host.initialized;
    g_callbacks_initialized = host.callbacks_initialized;
    g_ppu_interpreter = host.ppu_interpreter;
    g_spu_interpreter = host.spu_interpreter;
    g_jit = host.jit;
    g_renderer = host.renderer;
    set_message(host.message);
    return host.initialized && host.callbacks_initialized;
}

int rpcs3_ios_core_set_renderer(RPCS3IOSRendererBackend renderer)
{
    std::lock_guard lock(g_mutex);
    if (renderer != RPCS3IOSRendererVulkan && renderer != RPCS3IOSRendererMetal)
    {
        set_message("Unknown RPCS3 iOS renderer selection.");
        return 0;
    }

    std::string message;
    const bool selected = rpcs3::ios::upstream::select_renderer(upstream_renderer(renderer), message);
    set_message(std::move(message));
    return selected;
}

RPCS3IOSRendererBackend rpcs3_ios_core_get_renderer(void)
{
    std::lock_guard lock(g_mutex);
    return public_renderer(rpcs3::ios::upstream::selected_renderer());
}

int rpcs3_ios_core_boot_path(const char* path)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !g_callbacks_initialized)
    {
        set_message("The upstream execution host is not initialized.");
        return 0;
    }
    if (!valid_sandbox_path(path))
    {
        set_message("Boot input must exist inside the RPCS3 app container.");
        return 0;
    }

    g_last_boot_path = path;
    Emu.SetForceBoot(true);
    return boot_result(Emu.BootGame(g_last_boot_path, {}, true), "Boot");
}

int rpcs3_ios_core_boot_elf(const char* elf_path)
{
    return rpcs3_ios_core_boot_path(elf_path);
}

int rpcs3_ios_core_pause(void)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !Emu.IsRunning())
        return 0;
    const bool paused = Emu.Pause();
    set_message(paused ? "RPCS3 emulation paused." : "RPCS3 rejected the pause request.");
    return paused;
}

int rpcs3_ios_core_resume(void)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !Emu.IsPaused())
        return 0;
    Emu.Resume();
    set_message("RPCS3 emulation resumed.");
    return 1;
}

int rpcs3_ios_core_restart(void)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked)
        return 0;
    return boot_result(Emu.Restart(true), "Restart");
}

void rpcs3_ios_core_stop(void)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || Emu.IsStopped())
        return;
    Emu.Kill(true, false);
    set_message("RPCS3 emulation stopped.");
}

int rpcs3_ios_core_boot_vsh(void)
{
    const std::string vsh = g_layout.dev_flash + "/vsh/module/vsh.self";
    return rpcs3_ios_core_boot_path(vsh.c_str());
}

int rpcs3_ios_core_insert_disc(const char* path)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !valid_sandbox_path(path))
        return 0;
    return boot_result(Emu.InsertDisc(path), "Insert disc");
}

int rpcs3_ios_core_eject_disc(void)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked)
        return 0;
    Emu.EjectDisc();
    set_message("RPCS3 disc ejected.");
    return 1;
}

int rpcs3_ios_core_install_package(const char* path)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !valid_sandbox_path(path))
        return 0;
    const bool installed = rpcs3::utils::install_pkg(path);
    set_message(installed ? "RPCS3 installed the package." : "RPCS3 package installation failed.");
    return installed;
}

int rpcs3_ios_core_install_firmware(const char* path)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !valid_sandbox_path(path))
        return 0;
    std::string message;
    const bool installed = rpcs3::ios::upstream::install_firmware(path, message);
    set_message(std::move(message));
    return installed;
}

int rpcs3_ios_core_add_game(const char* path)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !valid_sandbox_path(path))
        return 0;
    return boot_result(Emu.AddGame(path), "Add game");
}

int rpcs3_ios_core_operation_available(RPCS3IOSCoreOperation operation)
{
    std::lock_guard lock(g_mutex);
    if (!g_runtime_linked || !g_callbacks_initialized)
        return 0;

    switch (operation)
    {
    case RPCS3IOSCoreOperationPause:
        return Emu.IsRunning();
    case RPCS3IOSCoreOperationResume:
        return Emu.IsPaused();
    case RPCS3IOSCoreOperationRestart:
    case RPCS3IOSCoreOperationStop:
    case RPCS3IOSCoreOperationInsertDisc:
    case RPCS3IOSCoreOperationEjectDisc:
        return !Emu.IsStopped();
    default:
        return 1;
    }
}
