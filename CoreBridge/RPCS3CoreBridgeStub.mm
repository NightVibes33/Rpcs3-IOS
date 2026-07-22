#include "RPCS3CoreBridge.h"
#include "IOSFilesystem.h"
#include "IOSPlatform.h"

#include <array>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>

namespace
{
std::mutex g_mutex;
bool g_platform_initialized = false;
RPCS3IOSCoreState g_state = RPCS3IOSCoreStateUnavailable;
std::string g_data_path;
std::string g_message = "RPCS3 iOS platform has not been initialized.";

void set_failure(std::string message)
{
    g_state = RPCS3IOSCoreStateFailed;
    g_message = std::move(message);
}
} // namespace

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void)
{
    const rpcs3::ios::platform_capabilities capabilities =
        rpcs3::ios::query_platform_capabilities();

    thread_local std::string message_copy;
    thread_local std::string path_copy;

    std::lock_guard lock(g_mutex);
    message_copy = g_message;
    path_copy = g_data_path;

    RPCS3IOSCoreDiagnostics result = {};
    result.state = g_state;
    result.platform_initialized = g_platform_initialized ? 1 : 0;
    result.ppu_interpreter_available = 0;
    result.spu_interpreter_available = 0;
    result.jit_available = capabilities.dynamic_code_supported ? 1 : 0;
    result.renderer_available = capabilities.metal_available ? 1 : 0;
    result.data_path = path_copy.empty() ? nullptr : path_copy.c_str();
    result.message = message_copy.c_str();
    return result;
}

int rpcs3_ios_core_initialize(const char *data_path)
{
    std::lock_guard lock(g_mutex);

    const rpcs3::ios::filesystem_layout layout =
        rpcs3::ios::prepare_filesystem_layout(data_path);
    if (!layout.ready)
    {
        g_platform_initialized = false;
        set_failure(layout.error.empty() ? "Unable to prepare RPCS3 sandbox storage" : layout.error);
        return 0;
    }

    const rpcs3::ios::platform_capabilities capabilities =
        rpcs3::ios::query_platform_capabilities();
    if (!capabilities.physical_device)
    {
        g_platform_initialized = false;
        set_failure("RPCS3 iOS requires a physical arm64 iOS device");
        return 0;
    }

    g_platform_initialized = true;
    g_data_path = layout.root;
    g_state = RPCS3IOSCoreStateUnavailable;
    g_message = capabilities.metal_available
        ? "Sandbox storage and Metal are ready. The upstream RPCS3 interpreter core is not linked yet."
        : "Sandbox storage is ready, but no Metal device is available.";
    return 1;
}

int rpcs3_ios_core_boot_elf(const char *elf_path)
{
    std::lock_guard lock(g_mutex);

    if (!g_platform_initialized)
    {
        set_failure("Initialize the iOS platform before loading an ELF");
        return 0;
    }

    if (!elf_path || !*elf_path)
    {
        set_failure("No ELF path was supplied");
        return 0;
    }

    if (!rpcs3::ios::path_is_within_app_container(elf_path))
    {
        set_failure("Boot input must be copied into the RPCS3 app container first");
        return 0;
    }

    std::error_code filesystem_error;
    if (!std::filesystem::is_regular_file(elf_path, filesystem_error))
    {
        set_failure("Boot input is not a readable regular file");
        return 0;
    }

    std::ifstream stream(elf_path, std::ios::binary);
    std::array<unsigned char, 4> magic{};
    stream.read(reinterpret_cast<char*>(magic.data()), static_cast<std::streamsize>(magic.size()));
    if (stream.gcount() != static_cast<std::streamsize>(magic.size()) ||
        magic[0] != 0x7f || magic[1] != 'E' || magic[2] != 'L' || magic[3] != 'F')
    {
        set_failure("Boot input does not contain an ELF header");
        return 0;
    }

    g_state = RPCS3IOSCoreStateUnavailable;
    g_message = "ELF header validated inside the app sandbox; interpreter execution is not linked yet.";
    return 0;
}

void rpcs3_ios_core_stop(void)
{
    std::lock_guard lock(g_mutex);
    if (g_platform_initialized)
    {
        g_state = RPCS3IOSCoreStateStopped;
        g_message = "Core stop requested; no upstream execution engine is linked.";
    }
}
