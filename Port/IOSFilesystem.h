#pragma once

#include <string>

namespace rpcs3::ios
{
struct filesystem_layout
{
    bool ready = false;
    std::string root;
    std::string config;
    std::string dev_hdd0;
    std::string dev_hdd1;
    std::string dev_flash;
    std::string cache;
    std::string logs;
    std::string imports;
    std::string error;
};

// Creates the RPCS3 directory layout inside this app's sandbox. A non-empty
// override is accepted only when it remains inside the current app container.
filesystem_layout prepare_filesystem_layout(const char* root_override = nullptr) noexcept;

// Lexical and symlink-resolved containment check for paths used by the core.
bool path_is_within_app_container(const char* path) noexcept;
} // namespace rpcs3::ios
