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

struct translated_shader
{
    shader_stage stage = shader_stage::vertex;
    std::string source;
    std::string entry_point;
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
