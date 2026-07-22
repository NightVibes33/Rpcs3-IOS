#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path


def replace_once(path: Path, needle: str, replacement: str, label: str) -> None:
    text = path.read_text(encoding="utf-8")
    if replacement in text:
        return
    if needle not in text:
        raise SystemExit(f"Unable to locate upstream {label} block in {path}")
    path.write_text(text.replace(needle, replacement, 1), encoding="utf-8")


def patch_shader_spirv_compile(upstream_root: Path) -> None:
    header = upstream_root / "rpcs3/Emu/RSX/VK/VKProgramPipeline.h"
    source = upstream_root / "rpcs3/Emu/RSX/VK/VKProgramPipeline.cpp"

    replace_once(
        header,
        '''\t\t\tVkShaderModule compile();

\t\t\tvoid destroy();''',
        '''\t\t\tbool compile_spirv();
\t\t\tVkShaderModule compile();

\t\t\tvoid destroy();''',
        "device-independent SPIR-V declaration",
    )

    replace_once(
        source,
        '''\t\tVkShaderModule shader::compile()
\t\t{
\t\t\tensure(m_handle == VK_NULL_HANDLE);

\t\t\tif (!spirv::compile_glsl_to_spv(m_compiled, m_source, type, ::glsl::glsl_rules_vulkan))
\t\t\t{
\t\t\t\trsx_log.notice("%s", m_source);
\t\t\t\tfmt::throw_exception("Failed to compile %s shader", to_string(type));
\t\t\t}

\t\t\tVkShaderModuleCreateInfo vs_info;
\t\t\tvs_info.codeSize = m_compiled.size() * sizeof(u32);
\t\t\tvs_info.pNext    = nullptr;
\t\t\tvs_info.sType    = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
\t\t\tvs_info.pCode    = m_compiled.data();
\t\t\tvs_info.flags    = 0;

\t\t\tvkCreateShaderModule(*g_render_device, &vs_info, nullptr, &m_handle);

\t\t\treturn m_handle;
\t\t}''',
        '''\t\tbool shader::compile_spirv()
\t\t{
\t\t\tm_compiled.clear();
\t\t\tif (!spirv::compile_glsl_to_spv(m_compiled, m_source, type, ::glsl::glsl_rules_vulkan))
\t\t\t{
\t\t\t\trsx_log.notice("%s", m_source);
\t\t\t\treturn false;
\t\t\t}
\t\t\treturn !m_compiled.empty();
\t\t}

\t\tVkShaderModule shader::compile()
\t\t{
\t\t\tensure(m_handle == VK_NULL_HANDLE);

\t\t\tif (!compile_spirv())
\t\t\t{
\t\t\t\tfmt::throw_exception("Failed to compile %s shader", to_string(type));
\t\t\t}

\t\t\tVkShaderModuleCreateInfo vs_info;
\t\t\tvs_info.codeSize = m_compiled.size() * sizeof(u32);
\t\t\tvs_info.pNext    = nullptr;
\t\t\tvs_info.sType    = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO;
\t\t\tvs_info.pCode    = m_compiled.data();
\t\t\tvs_info.flags    = 0;

\t\t\tvkCreateShaderModule(*g_render_device, &vs_info, nullptr, &m_handle);

\t\t\treturn m_handle;
\t\t}''',
        "device-independent SPIR-V implementation",
    )


def patch_vertex_frontend(upstream_root: Path) -> None:
    header = upstream_root / "rpcs3/Emu/RSX/VK/VKVertexProgram.h"
    source = upstream_root / "rpcs3/Emu/RSX/VK/VKVertexProgram.cpp"

    replace_once(
        header,
        '''\tvoid Task();
\tconst std::vector<vk::glsl::program_input>& get_inputs() { return inputs; }''',
        '''\tvoid Task();
\tvoid TaskForMetal();
\tconst std::vector<vk::glsl::program_input>& get_inputs() { return inputs; }''',
        "Metal vertex decompiler task declaration",
    )
    replace_once(
        header,
        '''\tvoid Decompile(const RSXVertexProgram& prog);
\tvoid Compile();''',
        '''\tvoid Decompile(const RSXVertexProgram& prog);
\tvoid DecompileForMetal(const RSXVertexProgram& prog);
\tvoid Compile();''',
        "Metal vertex frontend declaration",
    )
    replace_once(
        source,
        '''void VKVertexDecompilerThread::Task()
{
\tm_device_props.emulate_conditional_rendering = vk::emulate_conditional_rendering();
\tm_shader = Decompile();
\tvk_prog->SetInputs(inputs);
}''',
        '''void VKVertexDecompilerThread::Task()
{
\tm_device_props.emulate_conditional_rendering = vk::emulate_conditional_rendering();
\tm_shader = Decompile();
\tvk_prog->SetInputs(inputs);
}

void VKVertexDecompilerThread::TaskForMetal()
{
\t// Metal does not expose Vulkan conditional-rendering extensions. The RSX
\t// backend evaluates conditional rendering before submitting native draws.
\tm_device_props.emulate_conditional_rendering = false;
\tm_shader = Decompile();
\tvk_prog->SetInputs(inputs);
}''',
        "Metal vertex decompiler task",
    )
    replace_once(
        source,
        '''void VKVertexProgram::Decompile(const RSXVertexProgram& prog)
{
\tstd::string source;
\tVKVertexDecompilerThread decompiler(prog, source, parr, *this);
\tdecompiler.Task();

\thas_indexed_constants = decompiler.properties.has_indexed_constants;
\tconstant_ids = std::vector<u16>(decompiler.m_constant_ids.begin(), decompiler.m_constant_ids.end());

\tshader.create(::glsl::program_domain::glsl_vertex_program, source);
}''',
        '''void VKVertexProgram::Decompile(const RSXVertexProgram& prog)
{
\tstd::string source;
\tVKVertexDecompilerThread decompiler(prog, source, parr, *this);
\tdecompiler.Task();

\thas_indexed_constants = decompiler.properties.has_indexed_constants;
\tconstant_ids = std::vector<u16>(decompiler.m_constant_ids.begin(), decompiler.m_constant_ids.end());

\tshader.create(::glsl::program_domain::glsl_vertex_program, source);
}

void VKVertexProgram::DecompileForMetal(const RSXVertexProgram& prog)
{
\tstd::string source;
\tVKVertexDecompilerThread decompiler(prog, source, parr, *this);
\tdecompiler.TaskForMetal();

\thas_indexed_constants = decompiler.properties.has_indexed_constants;
\tconstant_ids = std::vector<u16>(decompiler.m_constant_ids.begin(), decompiler.m_constant_ids.end());

\tshader.create(::glsl::program_domain::glsl_vertex_program, source);
}''',
        "Metal vertex frontend implementation",
    )


def patch_fragment_frontend(upstream_root: Path) -> None:
    header = upstream_root / "rpcs3/Emu/RSX/VK/VKFragmentProgram.h"
    source = upstream_root / "rpcs3/Emu/RSX/VK/VKFragmentProgram.cpp"

    replace_once(
        header,
        '''\tvoid Task();
\tconst std::vector<vk::glsl::program_input>& get_inputs() { return inputs; }''',
        '''\tvoid Task();
\tvoid TaskForMetal();
\tconst std::vector<vk::glsl::program_input>& get_inputs() { return inputs; }''',
        "Metal fragment decompiler task declaration",
    )
    replace_once(
        header,
        '''\tvoid Decompile(const RSXFragmentProgram& prog);

\t/** Compile the decompiled fragment shader into a format we can use with OpenGL. */''',
        '''\tvoid Decompile(const RSXFragmentProgram& prog);
\tvoid DecompileForMetal(const RSXFragmentProgram& prog);

\t/** Compile the decompiled fragment shader into a format we can use with OpenGL. */''',
        "Metal fragment frontend declaration",
    )
    replace_once(
        source,
        '''void VKFragmentDecompilerThread::Task()
{
\tm_shader = Decompile();
\tvk_prog->SetInputs(inputs);
}''',
        '''void VKFragmentDecompilerThread::Task()
{
\tm_shader = Decompile();
\tvk_prog->SetInputs(inputs);
}

void VKFragmentDecompilerThread::TaskForMetal()
{
\t// Conservative capabilities shared by supported Apple GPUs. Native half
\t// arithmetic and D24 sampling can be enabled after per-device validation.
\tdevice_props.has_native_half_support = false;
\tdevice_props.emulate_depth_compare = true;
\tdevice_props.has_low_precision_rounding = false;
\tm_shader = Decompile();
\tvk_prog->SetInputs(inputs);
}''',
        "Metal fragment decompiler task",
    )
    replace_once(
        source,
        '''void VKFragmentProgram::Decompile(const RSXFragmentProgram& prog)
{
\tu32 size;
\tstd::string source;
\tVKFragmentDecompilerThread decompiler(source, parr, prog, size, *this);

\tconst auto pdev = vk::get_current_renderer();
\tif (g_cfg.video.shader_precision == gpu_preset_level::low)
\t{
\t\tdecompiler.device_props.has_native_half_support = pdev->get_shader_types_support().allow_float16;
\t}

\tdecompiler.device_props.emulate_depth_compare = !pdev->get_formats_support().d24_unorm_s8;
\tdecompiler.device_props.has_low_precision_rounding = vk::is_NVIDIA(vk::get_driver_vendor());
\tdecompiler.Task();

\tconstant_offsets = std::move(decompiler.properties.constant_offsets);
\tshader.create(::glsl::program_domain::glsl_fragment_program, source);
}''',
        '''void VKFragmentProgram::Decompile(const RSXFragmentProgram& prog)
{
\tu32 size;
\tstd::string source;
\tVKFragmentDecompilerThread decompiler(source, parr, prog, size, *this);

\tconst auto pdev = vk::get_current_renderer();
\tif (g_cfg.video.shader_precision == gpu_preset_level::low)
\t{
\t\tdecompiler.device_props.has_native_half_support = pdev->get_shader_types_support().allow_float16;
\t}

\tdecompiler.device_props.emulate_depth_compare = !pdev->get_formats_support().d24_unorm_s8;
\tdecompiler.device_props.has_low_precision_rounding = vk::is_NVIDIA(vk::get_driver_vendor());
\tdecompiler.Task();

\tconstant_offsets = std::move(decompiler.properties.constant_offsets);
\tshader.create(::glsl::program_domain::glsl_fragment_program, source);
}

void VKFragmentProgram::DecompileForMetal(const RSXFragmentProgram& prog)
{
\tu32 size;
\tstd::string source;
\tVKFragmentDecompilerThread decompiler(source, parr, prog, size, *this);
\tdecompiler.TaskForMetal();

\tconstant_offsets = std::move(decompiler.properties.constant_offsets);
\tshader.create(::glsl::program_domain::glsl_fragment_program, source);
}''',
        "Metal fragment frontend implementation",
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("upstream_root", type=Path)
    args = parser.parse_args()

    root = args.upstream_root.resolve()
    patch_shader_spirv_compile(root)
    patch_vertex_frontend(root)
    patch_fragment_frontend(root)
    print("Exposed RPCS3's existing RSX GLSL/SPIR-V frontend to the native Metal backend")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
