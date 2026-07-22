#include "RPCS3MetalRSXShaderFrontend.h"

#include "Emu/RSX/Program/SPIRVCommon.h"
#include "Emu/RSX/VK/VKFragmentProgram.h"
#include "Emu/RSX/VK/VKVertexProgram.h"

#include <exception>
#include <utility>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
shader_resource_kind translate_resource_kind(vk::glsl::program_input_type type)
{
    switch (type)
    {
    case vk::glsl::input_type_uniform_buffer:
        return shader_resource_kind::uniform_buffer;
    case vk::glsl::input_type_texel_buffer:
        return shader_resource_kind::texel_buffer;
    case vk::glsl::input_type_texture:
        return shader_resource_kind::texture;
    case vk::glsl::input_type_storage_buffer:
        return shader_resource_kind::storage_buffer;
    case vk::glsl::input_type_storage_texture:
        return shader_resource_kind::storage_texture;
    case vk::glsl::input_type_push_constant:
        return shader_resource_kind::push_constant;
    default:
        throw std::runtime_error("RPCS3 shader frontend emitted an unknown resource type.");
    }
}

std::vector<shader_resource_binding> translate_resources(
    const std::vector<vk::glsl::program_input>& inputs,
    shader_stage stage)
{
    std::vector<shader_resource_binding> resources;
    resources.reserve(inputs.size());

    for (const auto& input : inputs)
    {
        shader_resource_binding binding;
        binding.stage = stage;
        binding.kind = translate_resource_kind(input.type);
        binding.descriptor_set = input.set;
        binding.binding = input.location;
        binding.name = input.name;

        if (input.type == vk::glsl::input_type_push_constant)
        {
            const auto& push_constant = input.as_push_constant();
            binding.byte_offset = push_constant.offset;
            binding.byte_size = push_constant.size;
            // Push constants have no descriptor binding in Vulkan. Keep the
            // upstream sentinel out of the neutral Metal manifest.
            binding.binding = 0;
        }

        resources.push_back(std::move(binding));
    }

    return resources;
}
} // namespace

struct rsx_shader_frontend::implementation
{
    bool compiler_context_initialized = false;
};

rsx_shader_frontend::rsx_shader_frontend()
    : m_impl(std::make_unique<implementation>())
{
}

rsx_shader_frontend::~rsx_shader_frontend()
{
    shutdown();
}

bool rsx_shader_frontend::initialize(std::string& error)
{
    if (m_impl->compiler_context_initialized)
    {
        error.clear();
        return true;
    }

    try
    {
        spirv::initialize_compiler_context();
        m_impl->compiler_context_initialized = true;
        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        error = std::string("RPCS3 SPIR-V compiler initialization failed: ") + exception.what();
    }
    catch (...)
    {
        error = "RPCS3 SPIR-V compiler initialization failed with an unknown error.";
    }
    return false;
}

void rsx_shader_frontend::shutdown() noexcept
{
    if (!m_impl || !m_impl->compiler_context_initialized)
        return;

    spirv::finalize_compiler_context();
    m_impl->compiler_context_initialized = false;
}

bool rsx_shader_frontend::initialized() const noexcept
{
    return m_impl && m_impl->compiler_context_initialized;
}

bool rsx_shader_frontend::compile_vertex(
    const RSXVertexProgram& program,
    frontend_shader& output,
    std::string& error)
{
    output = {};
    output.stage = shader_stage::vertex;
    if (!initialized())
    {
        error = "RPCS3 RSX shader frontend is not initialized.";
        return false;
    }

    try
    {
        VKVertexProgram frontend;
        frontend.DecompileForMetal(program);
        if (!frontend.shader.compile_spirv())
        {
            error = "RPCS3 failed to compile the live RSX vertex program to SPIR-V.";
            return false;
        }

        output.spirv = frontend.shader.get_compiled();
        output.resources = translate_resources(frontend.uniforms, shader_stage::vertex);
        output.has_indexed_vertex_constants = frontend.has_indexed_constants;
        output.vertex_constant_ids.assign(frontend.constant_ids.begin(), frontend.constant_ids.end());
        if (output.spirv.empty())
        {
            error = "RPCS3 produced an empty SPIR-V vertex program.";
            return false;
        }

        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        error = std::string("Live RSX vertex shader compilation failed: ") + exception.what();
    }
    catch (...)
    {
        error = "Live RSX vertex shader compilation failed with an unknown error.";
    }
    output = {};
    output.stage = shader_stage::vertex;
    return false;
}

bool rsx_shader_frontend::compile_fragment(
    const RSXFragmentProgram& program,
    frontend_shader& output,
    std::string& error)
{
    output = {};
    output.stage = shader_stage::fragment;
    if (!initialized())
    {
        error = "RPCS3 RSX shader frontend is not initialized.";
        return false;
    }

    try
    {
        VKFragmentProgram frontend;
        frontend.DecompileForMetal(program);
        if (!frontend.shader.compile_spirv())
        {
            error = "RPCS3 failed to compile the live RSX fragment program to SPIR-V.";
            return false;
        }

        output.spirv = frontend.shader.get_compiled();
        output.resources = translate_resources(frontend.uniforms, shader_stage::fragment);
        output.fragment_constant_offsets.assign(
            frontend.constant_offsets.begin(), frontend.constant_offsets.end());
        if (output.spirv.empty())
        {
            error = "RPCS3 produced an empty SPIR-V fragment program.";
            return false;
        }

        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        error = std::string("Live RSX fragment shader compilation failed: ") + exception.what();
    }
    catch (...)
    {
        error = "Live RSX fragment shader compilation failed with an unknown error.";
    }
    output = {};
    output.stage = shader_stage::fragment;
    return false;
}
} // namespace rpcs3::ios::render::metal_rsx
