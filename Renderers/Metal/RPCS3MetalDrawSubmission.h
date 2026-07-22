#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace rpcs3::ios::render::metal_rsx
{
enum class index_format : std::uint8_t
{
    none,
    uint16,
    uint32,
};

enum class resource_stage : std::uint8_t
{
    vertex,
    fragment,
};

struct buffer_upload
{
    const void* bytes = nullptr;
    std::size_t byte_count = 0;
};

struct buffer_binding
{
    resource_stage stage = resource_stage::vertex;
    std::uint32_t index = 0;
    buffer_upload upload;
};

struct texture_buffer_binding
{
    resource_stage stage = resource_stage::vertex;
    std::uint32_t index = 0;
    std::uint32_t pixel_format = 0;
    std::uint32_t bytes_per_texel = 0;
    buffer_upload upload;
};

struct texture_binding
{
    resource_stage stage = resource_stage::fragment;
    std::uint32_t index = 0;
    void* texture = nullptr;
};

struct sampler_binding
{
    resource_stage stage = resource_stage::fragment;
    std::uint32_t index = 0;
    void* sampler = nullptr;
};

/*
 * Backend-neutral description of one already translated RSX draw.
 * Objective-C objects are carried as opaque retained handles so the public
 * renderer header stays valid C++ and the Metal implementation can bridge
 * them back to native Metal objects. Reflected SPIRV-Cross indices are carried
 * by the typed binding arrays rather than guessed by the renderer.
 */
struct draw_submission
{
    void* render_pipeline_state = nullptr;
    void* depth_stencil_state = nullptr;

    // Compatibility slot for simple tightly packed vertex data. Real RPCS3
    // vertex-fetch shaders use reflected buffer/texture-buffer bindings below.
    buffer_upload vertex_buffer;
    buffer_upload index_buffer;

    std::vector<buffer_binding> buffers;
    std::vector<texture_buffer_binding> texture_buffers;
    std::vector<texture_binding> textures;
    std::vector<sampler_binding> samplers;

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

    [[nodiscard]] bool has_vertex_resources() const noexcept
    {
        if (vertex_buffer.bytes && vertex_buffer.byte_count)
            return true;
        for (const auto& binding : buffers)
            if (binding.stage == resource_stage::vertex && binding.upload.bytes && binding.upload.byte_count)
                return true;
        for (const auto& binding : texture_buffers)
            if (binding.stage == resource_stage::vertex && binding.upload.bytes && binding.upload.byte_count)
                return true;
        return false;
    }
};

[[nodiscard]] bool validate_draw_submission(
    const draw_submission& submission,
    std::string& error) noexcept;
} // namespace rpcs3::ios::render::metal_rsx
