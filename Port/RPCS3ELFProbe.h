#pragma once

#include <cstdint>
#include <string>

namespace rpcs3::ios
{
struct elf_probe_result
{
    bool valid = false;
    bool ps3_compatible = false;
    std::uint64_t entry = 0;
    std::uint16_t program_header_count = 0;
    std::uint16_t section_header_count = 0;
    std::string description;
};

elf_probe_result probe_ps3_elf(const char* path) noexcept;
} // namespace rpcs3::ios
