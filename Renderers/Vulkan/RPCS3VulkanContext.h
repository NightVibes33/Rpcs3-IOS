#pragma once

#include <cstdint>
#include <memory>
#include <string>

namespace rpcs3::ios::render
{
struct vulkan_context_status
{
    bool initialized = false;
    bool surface_ready = false;
    bool frame_presented = false;
    std::string device_name;
    std::string message;
};

class vulkan_context
{
public:
    vulkan_context();
    ~vulkan_context();

    vulkan_context(const vulkan_context&) = delete;
    vulkan_context& operator=(const vulkan_context&) = delete;

    bool initialize(void* metal_layer,
                    std::uint32_t pixel_width,
                    std::uint32_t pixel_height,
                    bool vsync,
                    std::string& error);
    bool resize(std::uint32_t pixel_width,
                std::uint32_t pixel_height,
                std::string& error);
    bool present_clear(float red,
                       float green,
                       float blue,
                       float alpha,
                       std::string& error);
    void shutdown() noexcept;
    vulkan_context_status status() const;

private:
    struct implementation;
    std::unique_ptr<implementation> m_impl;
};
} // namespace rpcs3::ios::render
