#pragma once
#include <string>
namespace rpcs3::ios {
struct sfo_metadata { bool valid=false; std::string title; std::string title_id; std::string category; std::string app_version; std::string version; std::string description; };
sfo_metadata read_param_sfo(const char* path) noexcept;
}
