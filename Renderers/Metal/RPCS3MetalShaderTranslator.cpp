#include "RPCS3MetalShaderTranslator.h"

#include <spirv_msl.hpp>

#include <algorithm>
#include <exception>
#include <limits>
#include <utility>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
constexpr std::uint32_t spirv_magic = 0x07230203u;
constexpr std::uint32_t invalid_index = std::numeric_limits<std::uint32_t>::max();

spv::ExecutionModel execution_model(shader_stage stage) noexcept
{
    return stage == shader_stage::vertex
        ? spv::ExecutionModelVertex
        : spv::ExecutionModelFragment;
}

void append_reflected_resources(
    spirv_cross::CompilerMSL& compiler,
    const spirv_cross::SmallVector<spirv_cross::Resource>& resources,
    shader_resource_kind kind,
    std::vector<shader_resource_binding>& output)
{
    for (const spirv_cross::Resource& resource : resources)
    {
        shader_resource_binding binding;
        binding.kind = kind;
        binding.spirv_id = resource.id;
        binding.name = resource.name.empty() ? compiler.get_name(resource.id) : resource.name;

        if (kind == shader_resource_kind::push_constant)
        {
            binding.descriptor_set = invalid_index;
            binding.descriptor_binding = invalid_index;
        }
        else
        {
            binding.descriptor_set = compiler.has_decoration(resource.id, spv::DecorationDescriptorSet)
                ? compiler.get_decoration(resource.id, spv::DecorationDescriptorSet)
                : 0;
            binding.descriptor_binding = compiler.has_decoration(resource.id, spv::DecorationBinding)
                ? compiler.get_decoration(resource.id, spv::DecorationBinding)
                : 0;
        }

        binding.metal_index = compiler.get_automatic_msl_resource_binding(resource.id);
        binding.metal_secondary_index = compiler.get_automatic_msl_resource_binding_secondary(resource.id);
        output.emplace_back(std::move(binding));
    }
}

void reflect_resources(
    spirv_cross::CompilerMSL& compiler,
    const spirv_cross::ShaderResources& resources,
    std::vector<shader_resource_binding>& output)
{
    output.clear();
    append_reflected_resources(compiler, resources.uniform_buffers,
        shader_resource_kind::uniform_buffer, output);
    append_reflected_resources(compiler, resources.storage_buffers,
        shader_resource_kind::storage_buffer, output);
    append_reflected_resources(compiler, resources.sampled_images,
        shader_resource_kind::sampled_image, output);
    append_reflected_resources(compiler, resources.separate_images,
        shader_resource_kind::separate_image, output);
    append_reflected_resources(compiler, resources.separate_samplers,
        shader_resource_kind::separate_sampler, output);
    append_reflected_resources(compiler, resources.storage_images,
        shader_resource_kind::storage_image, output);
    append_reflected_resources(compiler, resources.subpass_inputs,
        shader_resource_kind::subpass_input, output);
    append_reflected_resources(compiler, resources.push_constant_buffers,
        shader_resource_kind::push_constant, output);
}
} // namespace

bool translate_spirv_to_msl(
    std::span<const std::uint32_t> spirv,
    shader_stage stage,
    translated_shader& output,
    std::string& error) noexcept
{
    output = {};
    output.stage = stage;

    if (spirv.size() < 5 || spirv.front() != spirv_magic)
    {
        error = "RSX shader translation received invalid SPIR-V.";
        return false;
    }

    try
    {
        std::vector<std::uint32_t> words(spirv.begin(), spirv.end());
        spirv_cross::CompilerMSL compiler(std::move(words));
        const spv::ExecutionModel requested_model = execution_model(stage);

        const auto entry_points = compiler.get_entry_points_and_stages();
        const auto entry = std::find_if(entry_points.begin(), entry_points.end(),
            [requested_model](const spirv_cross::EntryPoint& candidate)
            {
                return candidate.execution_model == requested_model;
            });
        if (entry == entry_points.end())
        {
            error = stage == shader_stage::vertex
                ? "SPIR-V module does not contain a vertex entry point."
                : "SPIR-V module does not contain a fragment entry point.";
            return false;
        }

        compiler.set_entry_point(entry->name, entry->execution_model);

        auto options = compiler.get_msl_options();
        options.platform = spirv_cross::CompilerMSL::Options::iOS;
        options.msl_version = spirv_cross::CompilerMSL::Options::make_msl_version(2, 4);
        options.enable_decoration_binding = true;
        options.ios_support_base_vertex_instance = true;
        options.texture_buffer_native = true;
        options.pad_fragment_output_components = true;
        compiler.set_msl_options(options);

        const spirv_cross::ShaderResources resources = compiler.get_shader_resources();
        output.entry_point = compiler.get_cleansed_entry_point_name(entry->name, entry->execution_model);
        output.source = compiler.compile();
        if (output.source.empty() || output.entry_point.empty())
        {
            error = "SPIRV-Cross returned an empty MSL shader or entry point.";
            output = {};
            output.stage = stage;
            return false;
        }

        reflect_resources(compiler, resources, output.resources);
        error.clear();
        return true;
    }
    catch (const spirv_cross::CompilerError& exception)
    {
        error = std::string("SPIR-V to MSL translation failed: ") + exception.what();
    }
    catch (const std::exception& exception)
    {
        error = std::string("Unexpected Metal shader translation failure: ") + exception.what();
    }
    catch (...)
    {
        error = "Unknown Metal shader translation failure.";
    }

    output = {};
    output.stage = stage;
    return false;
}
} // namespace rpcs3::ios::render::metal_rsx
