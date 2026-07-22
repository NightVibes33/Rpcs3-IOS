#pragma once

#include "RPCS3MetalPipelineState.h"

#include <cstddef>
#include <cstdint>
#include <memory>
#include <string>

namespace rpcs3::ios::render::metal_rsx
{
struct render_pipeline_request
{
    void* vertex_function = nullptr;
    void* fragment_function = nullptr;
    std::uint32_t color_pixel_format = 80; // MTLPixelFormatBGRA8Unorm
    std::uint32_t depth_pixel_format = 0;
    std::uint32_t stencil_pixel_format = 0;
    std::uint32_t sample_count = 1;
    color_blend_state color_blend;
};

struct compiled_render_pipeline
{
    void* state = nullptr;
};

class render_pipeline_cache final
{
public:
    render_pipeline_cache();
    ~render_pipeline_cache();

    render_pipeline_cache(const render_pipeline_cache&) = delete;
    render_pipeline_cache& operator=(const render_pipeline_cache&) = delete;

    bool initialize(void* metal_device, std::string& error);
    bool get_or_create(const render_pipeline_request& request,
                       compiled_render_pipeline& output,
                       std::string& error);
    void clear() noexcept;
    [[nodiscard]] bool initialized() const noexcept;
    [[nodiscard]] std::size_t size() const noexcept;

private:
    struct implementation;
    std::unique_ptr<implementation> m_impl;
};
} // namespace rpcs3::ios::render::metal_rsx
