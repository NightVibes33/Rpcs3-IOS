#pragma once

#include <cstdint>
#include <limits>
#include <span>
#include <string>
#include <vector>

namespace rpcs3::ios::render::metal_rsx
{
enum class shader_stage : std::uint8_t
{
    vertex,
    fragment,
};

enum class shader_resource_kind : std::uint8_t
{
    uniform_buffer,
    texel_buffer,
    texture,
    storage_buffer,
    storage_texture,
    push_constant,
};

inline constexpr std::uint32_t invalid_msl_resource_index =
    std::numeric_limits<std::uint32_t>::max();
inline constexpr std::uint32_t msl_push_constant_buffer_index = 16;

struct shader_resource_binding
{
    shader_stage stage = shader_stage::vertex;
    shader_resource_kind kind = shader_resource_kind::storage_buffer;
    std::uint32_t descriptor_set = 0;
    std::uint32_t binding = 0;
    std::uint32_t byte_offset = 0;
    std::uint32_t byte_size = 0;
    std::uint32_t msl_buffer = invalid_msl_resource_index;
    std::uint32_t msl_texture = invalid_msl_resource_index;
    std::uint32_t msl_sampler = invalid_msl_resource_index;
    bool used = false;
    std::string name;
};

struct translated_shader
{
    shader_stage stage = shader_stage::vertex;
    std::string source;
    std::string entry_point;
    std::vector<shader_resource_binding> resources;
};

/*
 * Assigns stable, non-overlapping classic Metal resource indices. RPCS3's
 * descriptor set and binding numbers remain the source of truth; the emitted
 * MSL slots are returned for the draw encoder to bind without guessing.
 */
[[nodiscard]] bool build_msl_resource_binding_plan(
    std::span<const shader_resource_binding> resources,
    shader_stage stage,
    std::vector<shader_resource_binding>& output,
    std::string& error) noexcept;

/*
 * Converts the SPIR-V emitted by RPCS3's existing RSX shader decompiler into
 * native iOS Metal Shading Language. This is the real bridge used between the
 * upstream shader frontend and the Metal pipeline cache; it does not generate
 * placeholder shaders.
 */
[[nodiscard]] bool translate_spirv_to_msl(
    std::span<const std::uint32_t> spirv,
    shader_stage stage,
    std::span<const shader_resource_binding> resources,
    translated_shader& output,
    std::string& error) noexcept;

[[nodiscard]] bool translate_spirv_to_msl(
    std::span<const std::uint32_t> spirv,
    shader_stage stage,
    translated_shader& output,
    std::string& error) noexcept;
} // namespace rpcs3::ios::render::metal_rsx
