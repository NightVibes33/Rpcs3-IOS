#include "RPCS3MetalGSRender.h"

#include "Emu/RSX/Common/BufferUtils.h"
#include "Emu/RSX/rsx_methods.h"
#include "Emu/RSX/rsx_utils.h"
#include "Utilities/Thread.h"

#import <Metal/Metal.h>

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <span>
#include <string>
#include <tuple>
#include <type_traits>
#include <variant>

namespace rpcs3::ios::render
{
namespace
{
template <typename T>
constexpr std::uint32_t rsx_value(T value) noexcept
{
    return static_cast<std::uint32_t>(value);
}

std::uint32_t color_mask_for_surface(unsigned index)
{
    std::uint32_t mask = 0;
    if (rsx::method_registers.color_mask_r(index)) mask |= 1u << 16;
    if (rsx::method_registers.color_mask_g(index)) mask |= 1u << 8;
    if (rsx::method_registers.color_mask_b(index)) mask |= 1u << 0;
    if (rsx::method_registers.color_mask_a(index)) mask |= 1u << 24;
    return mask;
}

metal_rsx::index_format metal_index_format(rsx::index_array_type type) noexcept
{
    return type == rsx::index_array_type::u16
        ? metal_rsx::index_format::uint16
        : metal_rsx::index_format::uint32;
}

bool metal_requires_index_expansion(rsx::primitive_type primitive) noexcept
{
    return metal_rsx::primitive_requires_index_expansion(rsx_value(primitive));
}
} // namespace

metal_gs_render::metal_gs_render(utils::serial* archive) noexcept
    : GSRender(archive)
{
}

u64 metal_gs_render::get_cycles()
{
    return thread_ctrl::get_cycles(static_cast<named_thread<metal_gs_render>&>(*this));
}

void metal_gs_render::on_init_thread()
{
    GSRender::on_init_thread();
    initialize_backend();
}

bool metal_gs_render::initialize_backend()
{
    if (m_backend_initialized)
        return true;
    if (!m_frame)
        return false;

    surface_config config;
    config.native_view = m_frame->handle();
    config.pixel_width = std::max(m_frame->client_width(), 1);
    config.pixel_height = std::max(m_frame->client_height(), 1);
    config.content_scale = 1.0f;
    config.vsync = true;

    std::string error;
    m_backend_initialized = m_backend.initialize(config, error);
    if (!m_backend_initialized)
        m_last_program_error = std::move(error);
    return m_backend_initialized;
}

void metal_gs_render::capture_rsx_draw_state()
{
    m_primitive_mapping = metal_rsx::map_primitive(
        rsx_value(rsx::method_registers.current_draw_clause.primitive));
    if (m_primitive_mapping.requires_index_rewrite)
        ++m_topology_rewrite_draws;

    m_depth_stencil_state.depth_test_enabled = rsx::method_registers.depth_test_enabled();
    m_depth_stencil_state.depth_write_enabled = rsx::method_registers.depth_write_enabled();
    m_depth_stencil_state.depth_compare_function = rsx_value(rsx::method_registers.depth_func());
    m_depth_stencil_state.stencil_test_enabled = rsx::method_registers.stencil_test_enabled();

    m_depth_stencil_state.front.compare_function = rsx_value(rsx::method_registers.stencil_func());
    m_depth_stencil_state.front.stencil_failure = rsx_value(rsx::method_registers.stencil_op_fail());
    m_depth_stencil_state.front.depth_failure = rsx_value(rsx::method_registers.stencil_op_zfail());
    m_depth_stencil_state.front.depth_stencil_pass = rsx_value(rsx::method_registers.stencil_op_zpass());
    m_depth_stencil_state.front.read_mask = rsx::method_registers.stencil_func_mask();
    m_depth_stencil_state.front.write_mask = rsx::method_registers.stencil_mask();

    if (rsx::method_registers.two_sided_stencil_test_enabled())
    {
        m_depth_stencil_state.back.compare_function = rsx_value(rsx::method_registers.back_stencil_func());
        m_depth_stencil_state.back.stencil_failure = rsx_value(rsx::method_registers.back_stencil_op_fail());
        m_depth_stencil_state.back.depth_failure = rsx_value(rsx::method_registers.back_stencil_op_zfail());
        m_depth_stencil_state.back.depth_stencil_pass = rsx_value(rsx::method_registers.back_stencil_op_zpass());
        m_depth_stencil_state.back.read_mask = rsx::method_registers.back_stencil_func_mask();
        m_depth_stencil_state.back.write_mask = rsx::method_registers.back_stencil_mask();
    }
    else
    {
        m_depth_stencil_state.back = m_depth_stencil_state.front;
    }

    m_color_blend_state.blend_enabled = rsx::method_registers.blend_enabled();
    m_color_blend_state.source_rgb_factor = rsx_value(rsx::method_registers.blend_func_sfactor_rgb());
    m_color_blend_state.destination_rgb_factor = rsx_value(rsx::method_registers.blend_func_dfactor_rgb());
    m_color_blend_state.rgb_equation = rsx_value(rsx::method_registers.blend_equation_rgb());
    m_color_blend_state.source_alpha_factor = rsx_value(rsx::method_registers.blend_func_sfactor_a());
    m_color_blend_state.destination_alpha_factor = rsx_value(rsx::method_registers.blend_func_dfactor_a());
    m_color_blend_state.alpha_equation = rsx_value(rsx::method_registers.blend_equation_a());
    m_color_blend_state.color_write_mask = color_mask_for_surface(0);

    ++m_translated_draws;
}

bool metal_gs_render::prepare_live_program_pipeline()
{
    if (!initialize_backend())
        return false;

    metal_rsx::compiled_rsx_programs programs;
    std::string error;
    if (!metal_rsx::compile_rsx_programs_to_spirv(
            current_vertex_program,
            current_fragment_program,
            programs,
            error))
    {
        ++m_program_compile_failures;
        m_last_program_error = std::move(error);
        return false;
    }

    metal_rsx::compiled_shader vertex_shader;
    if (!m_backend.compile_spirv_shader(
            std::span<const std::uint32_t>(programs.vertex_spirv),
            metal_rsx::shader_stage::vertex,
            vertex_shader,
            error))
    {
        ++m_program_compile_failures;
        m_last_program_error = std::move(error);
        return false;
    }

    metal_rsx::compiled_shader fragment_shader;
    if (!m_backend.compile_spirv_shader(
            std::span<const std::uint32_t>(programs.fragment_spirv),
            metal_rsx::shader_stage::fragment,
            fragment_shader,
            error))
    {
        ++m_program_compile_failures;
        m_last_program_error = std::move(error);
        return false;
    }

    metal_rsx::render_pipeline_request request;
    request.vertex_function = vertex_shader.function;
    request.fragment_function = fragment_shader.function;
    request.color_pixel_format = static_cast<std::uint32_t>(MTLPixelFormatBGRA8Unorm);
    request.depth_pixel_format = static_cast<std::uint32_t>(MTLPixelFormatInvalid);
    request.stencil_pixel_format = static_cast<std::uint32_t>(MTLPixelFormatInvalid);
    request.sample_count = 1;
    request.color_blend = m_color_blend_state;

    if (!m_backend.get_or_create_render_pipeline(request, m_active_pipeline, error))
    {
        ++m_program_compile_failures;
        m_last_program_error = std::move(error);
        return false;
    }

    ++m_program_ready_draws;
    m_last_program_error.clear();
    return true;
}

bool metal_gs_render::stage_live_geometry()
{
    m_staged_geometry.clear();
    m_vertex_layout.clear();
    m_draw_processor.analyse_inputs_interleaved(m_vertex_layout, current_vp_metadata);
    if (!m_vertex_layout.validate())
    {
        ++m_geometry_stage_failures;
        m_last_geometry_error = "RPCS3 reported no valid vertex inputs for the current draw.";
        return false;
    }

    auto& draw_clause = rsx::method_registers.current_draw_clause;
    const rsx::primitive_type primitive = draw_clause.primitive;
    const std::uint32_t input_count = draw_clause.get_elements_count();
    if (!input_count)
    {
        ++m_geometry_stage_failures;
        m_last_geometry_error = "RPCS3 reported an empty draw clause.";
        return false;
    }

    std::uint32_t min_index = 0;
    std::uint32_t max_index = 0;
    std::uint32_t vertex_index_offset = 0;
    bool index_rebase = false;
    bool command_valid = true;

    const auto command = m_draw_processor.get_draw_command(rsx::method_registers);
    std::visit([&](const auto& draw_command)
    {
        using command_type = std::decay_t<decltype(draw_command)>;

        if constexpr (std::is_same_v<command_type, rsx::draw_array_command>)
        {
            min_index = draw_clause.min_index();
            max_index = min_index + input_count - 1;
            m_staged_geometry.draw_count = input_count;

            if (metal_requires_index_expansion(primitive))
            {
                const std::uint32_t expanded_count = get_index_count(primitive, input_count);
                m_staged_geometry.index_bytes.resize(
                    static_cast<std::size_t>(expanded_count) * sizeof(std::uint16_t));
                write_index_array_for_non_indexed_non_native_primitive_to_buffer(
                    reinterpret_cast<char*>(m_staged_geometry.index_bytes.data()),
                    primitive,
                    input_count);
                m_staged_geometry.indices = metal_rsx::index_format::uint16;
                m_staged_geometry.draw_count = expanded_count;
            }
        }
        else if constexpr (std::is_same_v<command_type, rsx::draw_indexed_array_command>)
        {
            const rsx::index_array_type index_type = draw_clause.is_immediate_draw
                ? rsx::index_array_type::u32
                : rsx::method_registers.index_type();
            const std::uint32_t index_size = get_index_type_size(index_type);
            const std::uint32_t expanded_count = get_index_count(primitive, input_count);
            const std::uint32_t capacity_count = std::max(expanded_count, input_count * 4u);
            m_staged_geometry.index_bytes.resize(
                static_cast<std::size_t>(capacity_count) * index_size);

            std::uint32_t written_count = 0;
            std::tie(min_index, max_index, written_count) = write_index_array_data_to_buffer(
                std::span<std::byte>(m_staged_geometry.index_bytes),
                draw_command.raw_index_buffer,
                index_type,
                primitive,
                rsx::method_registers.restart_index_enabled(),
                rsx::method_registers.restart_index(),
                metal_requires_index_expansion);

            if (!written_count)
            {
                command_valid = false;
                return;
            }

            m_staged_geometry.index_bytes.resize(
                static_cast<std::size_t>(written_count) * index_size);
            m_staged_geometry.indices = metal_index_format(index_type);
            m_staged_geometry.draw_count = written_count;
            vertex_index_offset = rsx::method_registers.vertex_data_base_index();
            index_rebase = true;
        }
        else if constexpr (std::is_same_v<command_type, rsx::draw_inlined_array>)
        {
            if (m_vertex_layout.interleaved_blocks.empty() ||
                !m_vertex_layout.interleaved_blocks[0]->attribute_stride)
            {
                command_valid = false;
                return;
            }

            const std::uint32_t stride = m_vertex_layout.interleaved_blocks[0]->attribute_stride;
            const std::uint32_t inline_bytes =
                static_cast<std::uint32_t>(draw_clause.inline_vertex_array.size() * sizeof(std::uint32_t));
            const std::uint32_t inline_vertices = inline_bytes / stride;
            if (!inline_vertices)
            {
                command_valid = false;
                return;
            }

            min_index = 0;
            max_index = inline_vertices - 1;
            m_staged_geometry.draw_count = inline_vertices;

            if (metal_requires_index_expansion(primitive))
            {
                const std::uint32_t expanded_count = get_index_count(primitive, inline_vertices);
                m_staged_geometry.index_bytes.resize(
                    static_cast<std::size_t>(expanded_count) * sizeof(std::uint16_t));
                write_index_array_for_non_indexed_non_native_primitive_to_buffer(
                    reinterpret_cast<char*>(m_staged_geometry.index_bytes.data()),
                    primitive,
                    inline_vertices);
                m_staged_geometry.indices = metal_rsx::index_format::uint16;
                m_staged_geometry.draw_count = expanded_count;
            }
        }
        else
        {
            command_valid = false;
        }
    }, command);

    if (!command_valid || max_index < min_index || !m_staged_geometry.draw_count)
    {
        ++m_geometry_stage_failures;
        m_last_geometry_error = "RPCS3 could not normalize the current draw command for Metal staging.";
        m_staged_geometry.clear();
        return false;
    }

    std::uint32_t vertex_base = min_index;
    std::uint32_t vertex_base_index = 0;
    if (index_rebase)
    {
        vertex_base = rsx::get_index_from_base(
            min_index,
            rsx::method_registers.vertex_data_base_index());
        vertex_base_index = min_index;
    }

    const std::uint32_t vertex_count = (max_index - min_index) + 1;
    const auto required = calculate_memory_requirements(
        m_vertex_layout,
        vertex_base,
        vertex_count);

    m_staged_geometry.persistent_vertex_bytes.resize(required.first);
    m_staged_geometry.volatile_vertex_bytes.resize(required.second);
    m_draw_processor.write_vertex_data_to_memory(
        m_vertex_layout,
        vertex_base,
        vertex_count,
        required.first ? m_staged_geometry.persistent_vertex_bytes.data() : nullptr,
        required.second ? m_staged_geometry.volatile_vertex_bytes.data() : nullptr);

    m_draw_processor.fill_vertex_layout_state(
        m_vertex_layout,
        current_vp_metadata,
        vertex_base,
        vertex_count,
        m_staged_geometry.parameters.attrib_data.data(),
        0,
        0);

    m_staged_geometry.parameters.vertex_base_index = vertex_base_index;
    m_staged_geometry.parameters.vertex_index_offset = vertex_index_offset;
    m_staged_geometry.primitive_type = static_cast<std::uint32_t>(m_primitive_mapping.primitive);
    m_staged_geometry.first_vertex = vertex_base;
    m_staged_geometry.vertex_count = vertex_count;
    m_staged_geometry.base_vertex = 0;

    if (!m_staged_geometry.ready())
    {
        ++m_geometry_stage_failures;
        m_last_geometry_error = "RPCS3 produced no persistent or volatile vertex bytes for the current draw.";
        m_staged_geometry.clear();
        return false;
    }

    ++m_geometry_ready_draws;
    m_last_geometry_error.clear();
    return true;
}

void metal_gs_render::flip(const rsx::display_flip_info_t& info)
{
    if (initialize_backend())
    {
        const double phase = static_cast<double>(m_presented_frames) / 90.0;
        const float topology_signal = static_cast<float>((m_topology_rewrite_draws % 17) / 170.0);
        const float red = static_cast<float>(0.05 + 0.05 * (std::sin(phase) + 1.0)) + topology_signal;
        const float green = static_cast<float>(0.08 + 0.08 * (std::sin(phase + 2.1) + 1.0));
        const float blue = static_cast<float>(0.18 + 0.12 * (std::sin(phase + 4.2) + 1.0));
        std::string error;
        if (m_backend.present_test_frame(red, green, blue, 1.0f, error))
            ++m_presented_frames;
    }

    GSRender::flip(info);
}

void metal_gs_render::end()
{
    // Resolve real RSX programs and stage the exact persistent, volatile,
    // layout, and index payloads used by RPCS3's existing vertex fetch path.
    // Resource binding and command submission are intentionally gated until
    // reflected MSL indices are matched to these buffers.
    analyse_current_rsx_pipeline();
    capture_rsx_draw_state();
    const bool programs_ready = prepare_live_program_pipeline();
    const bool geometry_ready = stage_live_geometry();
    (void)programs_ready;
    (void)geometry_ready;
    execute_nop_draw();
    rsx::thread::end();
}
} // namespace rpcs3::ios::render
