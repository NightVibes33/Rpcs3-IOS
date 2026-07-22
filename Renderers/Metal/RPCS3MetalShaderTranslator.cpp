#include "RPCS3MetalShaderTranslator.h"

#include <spirv_msl.hpp>

#include <algorithm>
#include <exception>
#include <set>
#include <tuple>
#include <utility>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
constexpr std::uint32_t spirv_magic = 0x07230203u;
constexpr std::uint32_t maximum_classic_msl_buffers = 16;
constexpr std::uint32_t maximum_classic_msl_textures = 31;
constexpr std::uint32_t maximum_classic_msl_samplers = 16;

spv::ExecutionModel execution_model(shader_stage stage) noexcept
{
    return stage == shader_stage::vertex
        ? spv::ExecutionModelVertex
        : spv::ExecutionModelFragment;
}

bool allocate_index(std::uint32_t& next,
                    std::uint32_t maximum,
                    std::uint32_t& destination,
                    const char* resource_class,
                    std::string& error)
{
    if (next >= maximum)
    {
        error = std::string("RSX shader exceeds the native Metal ") +
            resource_class + " binding budget.";
        return false;
    }
    destination = next++;
    return true;
}

std::pair<std::uint32_t, std::uint32_t> spirv_binding_key(
    const shader_resource_binding& resource) noexcept
{
    if (resource.kind == shader_resource_kind::push_constant)
    {
        return {
            spirv_cross::kPushConstDescSet,
            spirv_cross::kPushConstBinding,
        };
    }
    return {resource.descriptor_set, resource.binding};
}
} // namespace

bool build_msl_resource_binding_plan(
    std::span<const shader_resource_binding> resources,
    shader_stage stage,
    std::vector<shader_resource_binding>& output,
    std::string& error) noexcept
{
    output.clear();
    std::uint32_t next_buffer = 0;
    std::uint32_t next_texture = 0;
    std::uint32_t next_sampler = 0;
    bool has_push_constants = false;
    std::set<std::pair<std::uint32_t, std::uint32_t>> occupied_spirv_bindings;

    try
    {
        for (const shader_resource_binding& input : resources)
        {
            if (input.stage != stage)
                continue;

            shader_resource_binding resource = input;
            resource.msl_buffer = invalid_msl_resource_index;
            resource.msl_texture = invalid_msl_resource_index;
            resource.msl_sampler = invalid_msl_resource_index;
            resource.used = false;

            const auto key = spirv_binding_key(resource);
            if (!occupied_spirv_bindings.emplace(key).second)
            {
                error = "RPCS3 shader frontend emitted duplicate descriptor set/binding metadata.";
                output.clear();
                return false;
            }

            switch (resource.kind)
            {
            case shader_resource_kind::uniform_buffer:
            case shader_resource_kind::storage_buffer:
                if (!allocate_index(next_buffer,
                                    maximum_classic_msl_buffers,
                                    resource.msl_buffer,
                                    "buffer",
                                    error))
                {
                    output.clear();
                    return false;
                }
                break;

            case shader_resource_kind::texel_buffer:
            case shader_resource_kind::storage_texture:
                if (!allocate_index(next_texture,
                                    maximum_classic_msl_textures,
                                    resource.msl_texture,
                                    "texture",
                                    error))
                {
                    output.clear();
                    return false;
                }
                break;

            case shader_resource_kind::texture:
                if (!allocate_index(next_texture,
                                    maximum_classic_msl_textures,
                                    resource.msl_texture,
                                    "texture",
                                    error) ||
                    !allocate_index(next_sampler,
                                    maximum_classic_msl_samplers,
                                    resource.msl_sampler,
                                    "sampler",
                                    error))
                {
                    output.clear();
                    return false;
                }
                break;

            case shader_resource_kind::push_constant:
                if (has_push_constants)
                {
                    error = "RPCS3 shader frontend emitted multiple push-constant ranges for one stage.";
                    output.clear();
                    return false;
                }
                has_push_constants = true;
                resource.msl_buffer = msl_push_constant_buffer_index;
                break;
            }

            output.push_back(std::move(resource));
        }
    }
    catch (const std::exception& exception)
    {
        error = std::string("Unable to assign native Metal resource bindings: ") + exception.what();
        output.clear();
        return false;
    }
    catch (...)
    {
        error = "Unable to assign native Metal resource bindings.";
        output.clear();
        return false;
    }

    error.clear();
    return true;
}

bool translate_spirv_to_msl(
    std::span<const std::uint32_t> spirv,
    shader_stage stage,
    std::span<const shader_resource_binding> resources,
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

    if (!build_msl_resource_binding_plan(resources, stage, output.resources, error))
        return false;

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

        for (const shader_resource_binding& resource : output.resources)
        {
            spirv_cross::MSLResourceBinding remap;
            remap.stage = requested_model;
            const auto [descriptor_set, binding] = spirv_binding_key(resource);
            remap.desc_set = descriptor_set;
            remap.binding = binding;
            remap.count = 1;
            if (resource.msl_buffer != invalid_msl_resource_index)
                remap.msl_buffer = resource.msl_buffer;
            if (resource.msl_texture != invalid_msl_resource_index)
                remap.msl_texture = resource.msl_texture;
            if (resource.msl_sampler != invalid_msl_resource_index)
                remap.msl_sampler = resource.msl_sampler;
            compiler.add_msl_resource_binding(remap);
        }

        output.entry_point = compiler.get_cleansed_entry_point_name(entry->name, entry->execution_model);
        output.source = compiler.compile();
        if (output.source.empty() || output.entry_point.empty())
        {
            error = "SPIRV-Cross returned an empty MSL shader or entry point.";
            output = {};
            output.stage = stage;
            return false;
        }

        for (shader_resource_binding& resource : output.resources)
        {
            const auto [descriptor_set, binding] = spirv_binding_key(resource);
            resource.used = compiler.is_msl_resource_binding_used(
                requested_model, descriptor_set, binding);
        }

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

bool translate_spirv_to_msl(
    std::span<const std::uint32_t> spirv,
    shader_stage stage,
    translated_shader& output,
    std::string& error) noexcept
{
    return translate_spirv_to_msl(spirv, stage, {}, output, error);
}
} // namespace rpcs3::ios::render::metal_rsx
