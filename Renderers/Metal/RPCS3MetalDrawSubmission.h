#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

namespace rpcs3::ios::render::metal_rsx
{
enum class index_format : std::uint8_t
{
    none,
    uint16,
    uint32,
};

struct buffer_upload
{
    const void* bytes = nullptr;
    std::size_t byte_count = 0;
};

/*
 * Backend-neutral description of one already translated RSX draw.
 * Objective-C objects are carried as opaque retained handles so the public
 * renderer header stays valid C++ and the Metal implementation can bridge
 * them back to id<MTLRenderPipelineState>/id<MTLDepthStencilState>.
 */
struct draw_submission
{
    void* render_pipeline_state = nullptr;
    void* depth_stencil_state = nullptr;

    buffer_upload vertex_buffer;
    buffer_upload index_buffer;

    std::uint32_t primitive_type = 3;
    index_format indices = index_format::none;
    std::uint32_t vertex_start = 0;
    std::uint32_t vertex_count = 0;
    std::uint32_t index_count = 0;
    std::uint32_t instance_count = 1;
    std::uint32_t stencil_reference_front = 0;
    std::uint32_t stencil_reference_back = 0;

    [[nodiscard]] bool indexed() const noexcept
    {
        return indices != index_format::none;
    }
};

[[nodiscard]] bool validate_draw_submission(
    const draw_submission& submission,
    std::string& error) noexcept;
} // namespace rpcs3::ios::render::metal_rsx
