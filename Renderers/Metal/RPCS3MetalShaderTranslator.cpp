#include "RPCS3MetalShaderTranslator.h"

#include <spirv_msl.hpp>

#include <algorithm>
#include <exception>
#include <utility>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
constexpr std::uint32_t spirv_magic = 0x07230203u;

spv::ExecutionModel execution_model(shader_stage stage) noexcept
{
    return stage == shader_stage::vertex
        ? spv::ExecutionModelVertex
        : spv::ExecutionModelFragment;
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

        output.entry_point = compiler.get_cleansed_entry_point_name(entry->name, entry->execution_model);
        output.source = compiler.compile();
        if (output.source.empty() || output.entry_point.empty())
        {
            error = "SPIRV-Cross returned an empty MSL shader or entry point.";
            output = {};
            output.stage = stage;
            return false;
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
} // namespace rpcs3::ios::render::metal_rsx
