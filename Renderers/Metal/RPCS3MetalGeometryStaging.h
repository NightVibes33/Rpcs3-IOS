#pragma once

#include "RPCS3MetalDrawSubmission.h"

#include <array>
#include <cstddef>
#include <cstdint>
#include <vector>

namespace rpcs3::ios::render::metal_rsx
{
// Binary-compatible with RPCS3's std430 draw_parameters_t declaration in
// RSXDefines2.glsl. The vertex shader reads this block to decode the staged
// persistent and volatile RSX vertex streams.
struct alignas(8) draw_parameters
{
    std::uint32_t vertex_base_index = 0;
    std::uint32_t vertex_index_offset = 0;
    std::uint32_t draw_id = 0;
    std::uint32_t xform_constants_offset = 0;
    std::uint32_t vs_context_offset = 0;
    std::uint32_t fs_constants_offset = 0;
    std::uint32_t fs_context_offset = 0;
    std::uint32_t fs_texture_base_index = 0;
    std::uint32_t fs_stipple_pattern_offset = 0;
    std::uint32_t reserved = 0;
    std::array<std::int32_t, 32> attrib_data{};
};

static_assert(sizeof(draw_parameters) == 168);
static_assert(alignof(draw_parameters) == 8);

struct staged_geometry
{
    std::vector<std::byte> persistent_vertex_bytes;
    std::vector<std::byte> volatile_vertex_bytes;
    std::vector<std::byte> index_bytes;
    draw_parameters parameters{};

    index_format indices = index_format::none;
    std::uint32_t primitive_type = 3;
    std::uint32_t first_vertex = 0;
    std::uint32_t vertex_count = 0;
    std::uint32_t draw_count = 0;
    std::int32_t base_vertex = 0;

    void clear()
    {
        persistent_vertex_bytes.clear();
        volatile_vertex_bytes.clear();
        index_bytes.clear();
        parameters = {};
        indices = index_format::none;
        primitive_type = 3;
        first_vertex = 0;
        vertex_count = 0;
        draw_count = 0;
        base_vertex = 0;
    }

    [[nodiscard]] bool indexed() const noexcept
    {
        return indices != index_format::none;
    }

    [[nodiscard]] bool ready() const noexcept
    {
        return vertex_count > 0 && draw_count > 0 &&
            (!persistent_vertex_bytes.empty() || !volatile_vertex_bytes.empty());
    }
};
} // namespace rpcs3::ios::render::metal_rsx
