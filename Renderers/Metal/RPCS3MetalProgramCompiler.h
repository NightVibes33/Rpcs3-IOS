#pragma once

#include <cstdint>
#include <string>
#include <vector>

struct RSXVertexProgram;
struct RSXFragmentProgram;

namespace rpcs3::ios::render::metal_rsx
{
struct compiled_rsx_programs
{
    std::vector<std::uint32_t> vertex_spirv;
    std::vector<std::uint32_t> fragment_spirv;
};

// Reuses RPCS3's existing RSX GLSL decompilers and SPIR-V compiler. This
// function produces backend-neutral SPIR-V only; Metal library and pipeline
// creation remain owned by metal_renderer.
bool compile_rsx_programs_to_spirv(const RSXVertexProgram& vertex_program,
                                   const RSXFragmentProgram& fragment_program,
                                   compiled_rsx_programs& output,
                                   std::string& error);
} // namespace rpcs3::ios::render::metal_rsx
