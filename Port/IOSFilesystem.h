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
    std::string dev_flash2;
    std::string dev_flash3;
    std::string dev_bdvd;
    std::string dev_usb000;
    std::string games;
    std::string packages;
    std::string cache;
    std::string logs;
    std::string imports;
    std::string firmware;
    std::string keys;
    std::string error;
};

// Creates RPCS3's standard VFS roots and guest directory tree inside the app
// sandbox. This mirrors the paths initialized by upstream Emulator::Init for
// user 00000001 and also creates package content-type destinations up front.
// A non-empty override is accepted only when it remains inside the app container.
filesystem_layout prepare_filesystem_layout(const char* root_override = nullptr) noexcept;

// Lexical and symlink-resolved containment check for paths used by the core.
bool path_is_within_app_container(const char* path) noexcept;
} // namespace rpcs3::ios
