#pragma once

#include <cstdint>
#include <string>

namespace rpcs3::ios
{
struct self_probe_result
{
    bool recognized = false;
    bool structurally_valid = false;
    bool contains_plain_elf = false;
    std::uint64_t elf_offset = 0;
    std::uint64_t file_size = 0;
    std::string description;
};

self_probe_result probe_ps3_self(const char* path);
} // namespace rpcs3::ios
