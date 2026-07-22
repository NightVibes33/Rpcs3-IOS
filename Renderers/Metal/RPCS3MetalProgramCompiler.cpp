#include "RPCS3MetalProgramCompiler.h"

#include "Emu/RSX/Program/GLSLTypes.h"
#include "Emu/RSX/Program/SPIRVCommon.h"
#include "Emu/RSX/VK/VKFragmentProgram.h"
#include "Emu/RSX/VK/VKVertexProgram.h"

#include <exception>
#include <mutex>
#include <string>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
void ensure_spirv_compiler_context()
{
    static std::once_flag initialized;
    std::call_once(initialized, []()
    {
        spirv::initialize_compiler_context();
    });
}

bool compile_stage(std::string source,
                   glsl::program_domain domain,
                   std::vector<std::uint32_t>& output,
                   const char* stage_name,
                   std::string& error)
{
    output.clear();
    if (source.empty())
    {
        error = std::string("RPCS3 produced an empty ") + stage_name + " GLSL program.";
        return false;
    }

    ensure_spirv_compiler_context();
    if (!spirv::compile_glsl_to_spv(output, source, domain, glsl::glsl_rules_vulkan))
    {
        error = std::string("RPCS3 failed to compile the live ") + stage_name + " GLSL program to SPIR-V.";
        output.clear();
        return false;
    }

    if (output.empty())
    {
        error = std::string("RPCS3 returned empty SPIR-V for the live ") + stage_name + " program.";
        return false;
    }

    return true;
}
} // namespace

bool compile_rsx_programs_to_spirv(const RSXVertexProgram& vertex_program,
                                   const RSXFragmentProgram& fragment_program,
                                   compiled_rsx_programs& output,
                                   std::string& error)
{
    output = {};

    try
    {
        VKVertexProgram vertex_backend_program;
        ParamArray ignored_vertex_parameters;
        std::string vertex_source;
        VKVertexDecompilerThread vertex_decompiler(
            vertex_program,
            vertex_source,
            ignored_vertex_parameters,
            vertex_backend_program);

        // Metal does not use Vulkan conditional-rendering extensions. The
        // renderer will handle conditional draws before submitting commands.
        vertex_decompiler.m_device_props.emulate_conditional_rendering = false;
        vertex_source = vertex_decompiler.Decompile();

        VKFragmentProgram fragment_backend_program;
        std::string fragment_source;
        u32 fragment_size = 0;
        VKFragmentDecompilerThread fragment_decompiler(
            fragment_source,
            fragment_backend_program.parr,
            fragment_program,
            fragment_size,
            fragment_backend_program);

        // Use conservative capabilities until resource binding and native
        // depth-compare behavior are verified against real RSX workloads.
        fragment_decompiler.device_props.has_native_half_support = false;
        fragment_decompiler.device_props.emulate_depth_compare = false;
        fragment_decompiler.device_props.has_low_precision_rounding = false;
        fragment_source = fragment_decompiler.Decompile();

        if (!compile_stage(std::move(vertex_source),
                           glsl::glsl_vertex_program,
                           output.vertex_spirv,
                           "vertex",
                           error))
        {
            return false;
        }

        if (!compile_stage(std::move(fragment_source),
                           glsl::glsl_fragment_program,
                           output.fragment_spirv,
                           "fragment",
                           error))
        {
            output.vertex_spirv.clear();
            return false;
        }

        error.clear();
        return true;
    }
    catch (const std::exception& exception)
    {
        output = {};
        error = std::string("RPCS3 live RSX program decompilation failed: ") + exception.what();
        return false;
    }
    catch (...)
    {
        output = {};
        error = "RPCS3 live RSX program decompilation failed with an unknown error.";
        return false;
    }
}
} // namespace rpcs3::ios::render::metal_rsx
