#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace rpcs3::ios
{
struct runtime_capabilities
{
    bool ppu_interpreter = false;
    bool spu_interpreter = false;
    bool syscall_dispatch = false;
    bool audio_backend = false;
    bool metal_backend = false;
};

struct runtime_result
{
    bool ready = false;
    std::uint64_t entry = 0;
    std::size_t mapped_bytes = 0;
    std::string description;
};

runtime_capabilities query_runtime_capabilities() noexcept;
runtime_result prepare_runtime_image(const char* elf_path) noexcept;
void stop_runtime() noexcept;
}
