#pragma once

#include "RPCS3MetalShaderTranslator.h"

#include <cstdint>
#include <string>
#include <vector>

namespace rpcs3::ios::render::metal_rsx
{
constexpr std::uint32_t invalid_metal_resource_index = UINT32_MAX;

struct vertex_resource_bindings
{
    std::uint32_t persistent_vertex_texture = invalid_metal_resource_index;
    std::uint32_t transient_vertex_texture = invalid_metal_resource_index;
    std::uint32_t draw_parameters_buffer = invalid_metal_resource_index;
    std::uint32_t vertex_context_buffer = invalid_metal_resource_index;
    std::uint32_t push_constant_buffer = invalid_metal_resource_index;

    [[nodiscard]] bool complete() const noexcept;
};

/*
 * RPCS3's Vulkan vertex decompiler assigns descriptor set 0 bindings as:
 *   0 persistent vertex texel buffer
 *   1 transient vertex texel buffer
 *   2 draw parameters / vertex layout storage buffer
 *   3 vertex context storage buffer
 * SPIRV-Cross may assign different Metal texture and buffer indices, so this
 * resolver records the actual post-translation indices.
 */
[[nodiscard]] bool resolve_vertex_resource_bindings(
    const std::vector<shader_resource_binding>& resources,
    vertex_resource_bindings& output,
    std::string& error);
} // namespace rpcs3::ios::render::metal_rsx
