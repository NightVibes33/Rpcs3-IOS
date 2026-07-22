#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace rpcs3::ios
{
struct self_segment_mapping
{
    std::uint64_t source_offset = 0;
    std::uint64_t source_size = 0;
    std::uint64_t elf_file_offset = 0;
    std::uint64_t virtual_address = 0;
    std::uint64_t memory_size = 0;
    std::uint32_t flags = 0;
};

struct self_load_plan
{
    bool valid = false;
    bool ready_for_plain_extraction = false;
    std::uint64_t entry = 0;
    std::vector<self_segment_mapping> segments;
    std::string description;
};

self_load_plan build_plain_self_load_plan(const char* path) noexcept;
} // namespace rpcs3::ios
