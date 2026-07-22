#include "RPCS3CoreBridge.h"

#include <cstdlib>

namespace
{
RPCS3IOSRendererBackend g_selected_renderer = RPCS3IOSRendererVulkan;

int execution_unavailable()
{
    const RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    return diagnostics.capability_level == RPCS3IOSCoreCapabilityExecutionCapable &&
           diagnostics.upstream_runtime_linked && diagnostics.host_callbacks_initialized;
}
}

int rpcs3_ios_core_set_renderer(RPCS3IOSRendererBackend renderer)
{
    if (renderer != RPCS3IOSRendererVulkan && renderer != RPCS3IOSRendererMetal)
        return 0;
    g_selected_renderer = renderer;
    setenv("RPCS3_IOS_RENDERER", renderer == RPCS3IOSRendererMetal ? "metal" : "vulkan", 1);
    return 1;
}

RPCS3IOSRendererBackend rpcs3_ios_core_get_renderer(void)
{
    return g_selected_renderer;
}

int rpcs3_ios_core_boot_path(const char* path)
{
    return rpcs3_ios_core_boot_elf(path);
}

int rpcs3_ios_core_pause(void)
{
    return 0;
}

int rpcs3_ios_core_resume(void)
{
    return 0;
}

int rpcs3_ios_core_restart(void)
{
    return 0;
}

int rpcs3_ios_core_boot_vsh(void)
{
    return 0;
}

int rpcs3_ios_core_insert_disc(const char* path)
{
    (void)path;
    return 0;
}

int rpcs3_ios_core_eject_disc(void)
{
    return 0;
}

int rpcs3_ios_core_install_package(const char* path)
{
    (void)path;
    return 0;
}

int rpcs3_ios_core_install_firmware(const char* path)
{
    (void)path;
    return 0;
}

int rpcs3_ios_core_add_game(const char* path)
{
    (void)path;
    return 0;
}

int rpcs3_ios_core_operation_available(RPCS3IOSCoreOperation operation)
{
    (void)operation;
    return execution_unavailable();
}
