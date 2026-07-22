#pragma once

#include <cstdint>
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
    storage_buffer,
    sampled_image,
    separate_image,
    separate_sampler,
    storage_image,
    subpass_input,
    push_constant,
};

struct shader_resource_binding
{
    shader_resource_kind kind = shader_resource_kind::uniform_buffer;
    std::uint32_t spirv_id = 0;
    std::uint32_t descriptor_set = 0;
    std::uint32_t descriptor_binding = 0;
    std::uint32_t metal_index = UINT32_MAX;
    std::uint32_t metal_secondary_index = UINT32_MAX;
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
 * Converts the SPIR-V emitted by RPCS3's existing RSX shader decompiler into
 * native iOS Metal Shading Language. This is the real bridge used between the
 * upstream shader frontend and the Metal pipeline cache; it does not generate
 * placeholder shaders.
 */
[[nodiscard]] bool translate_spirv_to_msl(
    std::span<const std::uint32_t> spirv,
    shader_stage stage,
    translated_shader& output,
    std::string& error) noexcept;
} // namespace rpcs3::ios::render::metal_rsx
