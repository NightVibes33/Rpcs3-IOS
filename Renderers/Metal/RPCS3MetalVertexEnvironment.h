#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <string>

namespace rpcs3::ios::render::metal_rsx
{
/* Matches vertex_context_t in RPCS3's RSXDefines2.glsl (std430, 96 bytes). */
struct alignas(16) vertex_context_record
{
    std::array<float, 16> scale_offset_matrix{};
    std::uint32_t user_clip_configuration_bits = 0;
    std::uint32_t transform_branch_bits = 0;
    float point_size = 1.0f;
    float z_near = 0.0f;
    float z_far = 1.0f;
    std::array<float, 3> reserved{};
};

/* Matches draw_parameters_t in RPCS3's RSXDefines2.glsl (std430, 168 bytes). */
#pragma pack(push, 1)
struct draw_parameters_record
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
#pragma pack(pop)

static_assert(sizeof(vertex_context_record) == 96,
    "RPCS3 Metal vertex context must match the shader's 96-byte std430 record");
static_assert(alignof(vertex_context_record) == 16,
    "RPCS3 Metal vertex context must retain 16-byte matrix alignment");
static_assert(sizeof(draw_parameters_record) == 168,
    "RPCS3 Metal draw parameters must match the shader's 168-byte std430 record");
static_assert(offsetof(draw_parameters_record, attrib_data) == 40,
    "RPCS3 Metal vertex descriptors must begin at byte 40");

bool validate_vertex_environment(const vertex_context_record& context,
                                 const draw_parameters_record& parameters,
                                 std::string& error);
} // namespace rpcs3::ios::render::metal_rsx
