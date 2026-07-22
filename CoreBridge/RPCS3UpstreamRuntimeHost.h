#pragma once

#include <string>

namespace rpcs3::ios
{
struct filesystem_layout;

namespace upstream
{
enum class renderer_backend
{
    vulkan,
    metal,
};

struct runtime_host_status
{
    bool initialized = false;
    bool callbacks_initialized = false;
    bool ppu_interpreter = false;
    bool spu_interpreter = false;
    bool jit = false;
    bool renderer = false;
    renderer_backend selected_renderer = renderer_backend::vulkan;
    std::string message;
};

/* Selects which GSRender implementation is created on the next guest boot. */
bool select_renderer(renderer_backend renderer, std::string& message);
renderer_backend selected_renderer() noexcept;

/*
 * Initializes RPCS3's real Emu singleton and installs the iOS host callbacks.
 * This function is compiled only in the execution-capable CMake graph where the
 * upstream rpcs3_emu target is linked directly into the Qt iOS application.
 */
runtime_host_status initialize_runtime_host(const filesystem_layout& layout);

/* Installs PS3UPDAT.PUP into the sandbox dev_flash tree through RPCS3 loaders. */
bool install_firmware(const std::string& pup_path, std::string& message);
} // namespace upstream
} // namespace rpcs3::ios
