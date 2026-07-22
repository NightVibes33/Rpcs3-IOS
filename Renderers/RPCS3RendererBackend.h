#pragma once

#include <cstdint>
#include <memory>
#include <string>

namespace rpcs3::ios::render
{
enum class backend_kind : std::uint32_t
{
    vulkan = 0,
    metal = 1,
};

struct surface_config
{
    void* native_view = nullptr;
    std::uint32_t pixel_width = 1;
    std::uint32_t pixel_height = 1;
    float content_scale = 1.0f;
    bool vsync = true;
};

struct backend_status
{
    backend_kind kind = backend_kind::metal;
    bool compiled = false;
    bool initialized = false;
    bool surface_ready = false;
    bool frame_presented = false;
    std::string device_name;
    std::string message;
};

class renderer_backend
{
public:
    virtual ~renderer_backend() = default;

    virtual backend_kind kind() const noexcept = 0;
    virtual bool initialize(const surface_config& config, std::string& error) = 0;
    virtual bool resize(std::uint32_t pixel_width,
                        std::uint32_t pixel_height,
                        float content_scale,
                        std::string& error) = 0;
    virtual bool present_test_frame(float red,
                                    float green,
                                    float blue,
                                    float alpha,
                                    std::string& error) = 0;
    virtual void shutdown() noexcept = 0;
    virtual backend_status status() const = 0;
};

std::unique_ptr<renderer_backend> create_renderer_backend(backend_kind kind);
bool renderer_backend_compiled(backend_kind kind) noexcept;
const char* renderer_backend_name(backend_kind kind) noexcept;
} // namespace rpcs3::ios::render
