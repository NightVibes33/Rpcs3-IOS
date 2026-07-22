#pragma once

#include "RPCS3MetalShaderTranslator.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

struct RSXVertexProgram;
struct RSXFragmentProgram;

namespace rpcs3::ios::render::metal_rsx
{
enum class shader_resource_kind : std::uint8_t
{
    uniform_buffer,
    texel_buffer,
    texture,
    storage_buffer,
    storage_texture,
    push_constant,
};

struct shader_resource_binding
{
    shader_stage stage = shader_stage::vertex;
    shader_resource_kind kind = shader_resource_kind::storage_buffer;
    std::uint32_t descriptor_set = 0;
    std::uint32_t binding = 0;
    std::uint32_t byte_offset = 0;
    std::uint32_t byte_size = 0;
    std::string name;
};

struct frontend_shader
{
    shader_stage stage = shader_stage::vertex;
    std::vector<std::uint32_t> spirv;
    std::vector<shader_resource_binding> resources;
    std::vector<std::uint32_t> fragment_constant_offsets;
    bool has_indexed_vertex_constants = false;
    std::vector<std::uint16_t> vertex_constant_ids;
};

/*
 * Reuses RPCS3's existing RSX -> Vulkan GLSL frontend and glslang compiler,
 * but stops before Vulkan shader-module creation. The resulting SPIR-V and
 * binding manifest are consumed by the native Metal translator/cache.
 */
class rsx_shader_frontend final
{
public:
    rsx_shader_frontend();
    ~rsx_shader_frontend();

    rsx_shader_frontend(const rsx_shader_frontend&) = delete;
    rsx_shader_frontend& operator=(const rsx_shader_frontend&) = delete;

    bool initialize(std::string& error);
    void shutdown() noexcept;
    [[nodiscard]] bool initialized() const noexcept;

    bool compile_vertex(const RSXVertexProgram& program,
                        frontend_shader& output,
                        std::string& error);
    bool compile_fragment(const RSXFragmentProgram& program,
                          frontend_shader& output,
                          std::string& error);

private:
    struct implementation;
    std::unique_ptr<implementation> m_impl;
};
} // namespace rpcs3::ios::render::metal_rsx
