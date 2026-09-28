#pragma once

#include <string>

namespace rpcs3::ios
{
struct self_extraction_result
{
    bool success = false;
    std::string output_path;
    std::string description;
};

self_extraction_result extract_plain_self_to_elf(
    const char* self_path,
    const char* output_path) noexcept;
} // namespace rpcs3::ios
