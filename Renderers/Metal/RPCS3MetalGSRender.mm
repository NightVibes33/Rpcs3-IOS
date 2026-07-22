#include "RPCS3MetalGSRender.h"

#include "Emu/RSX/Common/BufferUtils.h"
#include "Emu/RSX/Program/ProgramStateCache.h"
#include "Emu/RSX/rsx_methods.h"
#include "Emu/RSX/rsx_utils.h"
#include "RPCS3MetalPrimitiveExpander.h"
#include "Utilities/Thread.h"

#import <Metal/Metal.h>

#include <algorithm>
#include <cmath>
#include <cstring>
#include <span>
#include <string>
#include <tuple>
#include <type_traits>
#include <utility>
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

void store_u32_indices(const std::vector<std::uint32_t>& indices,
                       std::vector<std::byte>& destination)
{
    destination.resize(indices.size() * sizeof(std::uint32_t));
    if (!destination.empty())
        std::memcpy(destination.data(), indices.data(), destination.size());
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

    @autoreleasepool
    {
        MTLDepthStencilDescriptor* depth_stencil = [[MTLDepthStencilDescriptor alloc] init];
        metal_rsx::configure_depth_stencil_descriptor(depth_stencil, m_depth_stencil_state);

        MTLRenderPipelineDescriptor* pipeline = [[MTLRenderPipelineDescriptor alloc] init];
        metal_rsx::configure_color_attachment(pipeline.colorAttachments[0], m_color_blend_state);
        pipeline.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    }

    ++m_translated_draws;
}

bool metal_gs_render::prepare_live_program_pipeline()
{
    if (!initialize_backend())
        return false;

    const usz vertex_hash = program_hash_util::vertex_program_storage_hash{}(current_vertex_program);
    const usz fragment_hash = program_hash_util::fragment_program_storage_hash{}(current_fragment_program);
    const bool program_cache_hit = m_cached_program_pair_valid &&
        m_cached_vertex_program_hash == vertex_hash &&
        m_cached_fragment_program_hash == fragment_hash;

    std::string error;
    if (!program_cache_hit)
    {
        metal_rsx::compiled_rsx_programs programs;
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

        metal_rsx::vertex_resource_bindings vertex_bindings;
        if (!metal_rsx::resolve_vertex_resource_bindings(
                vertex_shader.resources,
                vertex_bindings,
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

        m_cached_vertex_shader = std::move(vertex_shader);
        m_cached_fragment_shader = std::move(fragment_shader);
        m_vertex_bindings = vertex_bindings;
        m_cached_vertex_program_hash = vertex_hash;
        m_cached_fragment_program_hash = fragment_hash;
        m_cached_program_pair_valid = true;
        ++m_program_cache_misses;
    }
    else
    {
        if (!m_vertex_bindings.complete())
        {
            ++m_program_compile_failures;
            m_last_program_error = "Cached RPCS3 Metal program has incomplete reflected vertex bindings.";
            return false;
        }
        ++m_program_cache_hits;
    }

    metal_rsx::render_pipeline_request request;
    request.vertex_function = m_cached_vertex_shader.function;
    request.fragment_function = m_cached_fragment_shader.function;
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

bool metal_gs_render::prepare_live_geometry_packet()
{
    m_geometry_packet.clear();
    m_vertex_layout.clear();
    m_draw_processor.analyse_inputs_interleaved(m_vertex_layout, current_vp_metadata);
    if (!m_vertex_layout.validate())
    {
        ++m_geometry_failures;
        m_last_geometry_error = "RPCS3 produced no usable vertex input layout for the live Metal draw.";
        return false;
    }

    const auto& clause = rsx::method_registers.current_draw_clause;
    const std::uint32_t gcm_primitive = rsx_value(clause.primitive);
    std::uint32_t vertex_base = 0;
    std::uint32_t vertex_count = 0;
    std::uint32_t draw_count = 0;
    std::uint32_t min_index = 0;
    std::uint32_t max_index = 0;
    std::uint32_t vertex_index_base = 0;
    std::uint32_t vertex_index_offset = 0;
    bool indexed = false;
    bool topology_rewritten = false;
    bool primitive_restart_present = false;
    metal_rsx::geometry_index_format index_format = metal_rsx::geometry_index_format::none;

    const auto command = m_draw_processor.get_draw_command(rsx::method_registers);
    std::visit([&](const auto& draw_command)
    {
        using command_type = std::decay_t<decltype(draw_command)>;
        if constexpr (std::is_same_v<command_type, rsx::draw_array_command>)
        {
            vertex_count = clause.get_elements_count();
            min_index = clause.min_index();
            max_index = vertex_count ? min_index + vertex_count - 1 : min_index;
            vertex_base = min_index;
            draw_count = vertex_count;

            if (metal_rsx::primitive_requires_index_expansion(gcm_primitive))
            {
                const auto indices = metal_rsx::make_and_expand_sequential_indices(gcm_primitive, vertex_count);
                store_u32_indices(indices, m_geometry_packet.index_bytes);
                indexed = true;
                topology_rewritten = true;
                index_format = metal_rsx::geometry_index_format::uint32;
                draw_count = static_cast<std::uint32_t>(indices.size());
            }
        }
        else if constexpr (std::is_same_v<command_type, rsx::draw_inlined_array>)
        {
            if (m_vertex_layout.interleaved_blocks.empty() ||
                m_vertex_layout.interleaved_blocks[0]->attribute_stride == 0)
            {
                return;
            }

            const std::size_t stream_bytes = clause.inline_vertex_array.size() * sizeof(std::uint32_t);
            vertex_count = static_cast<std::uint32_t>(
                stream_bytes / m_vertex_layout.interleaved_blocks[0]->attribute_stride);
            min_index = 0;
            max_index = vertex_count ? vertex_count - 1 : 0;
            vertex_base = 0;
            draw_count = vertex_count;

            if (metal_rsx::primitive_requires_index_expansion(gcm_primitive))
            {
                const auto indices = metal_rsx::make_and_expand_sequential_indices(gcm_primitive, vertex_count);
                store_u32_indices(indices, m_geometry_packet.index_bytes);
                indexed = true;
                topology_rewritten = true;
                index_format = metal_rsx::geometry_index_format::uint32;
                draw_count = static_cast<std::uint32_t>(indices.size());
            }
        }
        else if constexpr (std::is_same_v<command_type, rsx::draw_indexed_array_command>)
        {
            const rsx::index_array_type rsx_index_type = clause.is_immediate_draw
                ? rsx::index_array_type::u32
                : rsx::method_registers.index_type();
            const std::uint32_t index_size = get_index_type_size(rsx_index_type);
            const std::uint32_t source_count = clause.get_elements_count();
            std::uint32_t capacity_count = std::max(source_count, get_index_count(clause.primitive, source_count));
            primitive_restart_present = rsx::method_registers.restart_index_enabled();
            if (primitive_restart_present)
                capacity_count *= 2;
            capacity_count += 16;

            m_geometry_packet.index_bytes.resize(
                static_cast<std::size_t>(capacity_count) * index_size);
            auto destination = std::span<std::byte>(
                m_geometry_packet.index_bytes.data(),
                m_geometry_packet.index_bytes.size());

            std::uint32_t written_count = 0;
            std::tie(min_index, max_index, written_count) = write_index_array_data_to_buffer(
                destination,
                draw_command.raw_index_buffer,
                rsx_index_type,
                clause.primitive,
                primitive_restart_present,
                rsx::method_registers.restart_index(),
                [](rsx::primitive_type primitive)
                {
                    return metal_rsx::primitive_requires_index_expansion(rsx_value(primitive));
                });

            m_geometry_packet.index_bytes.resize(
                static_cast<std::size_t>(written_count) * index_size);
            indexed = written_count != 0;
            topology_rewritten = metal_rsx::primitive_requires_index_expansion(gcm_primitive);
            index_format = rsx_index_type == rsx::index_array_type::u16
                ? metal_rsx::geometry_index_format::uint16
                : metal_rsx::geometry_index_format::uint32;
            draw_count = written_count;
            vertex_count = written_count && max_index >= min_index
                ? (max_index - min_index) + 1
                : 0;
            vertex_base = vertex_count
                ? rsx::get_index_from_base(min_index, rsx::method_registers.vertex_data_base_index())
                : 0;
            vertex_index_base = min_index;
            vertex_index_offset = rsx::method_registers.vertex_data_base_index();
        }
    }, command);

    if (vertex_count == 0 || draw_count == 0)
    {
        ++m_geometry_failures;
        m_geometry_packet.clear();
        m_last_geometry_error = "RPCS3 live draw resolved to an empty Metal geometry range.";
        return false;
    }

    const auto required = calculate_memory_requirements(m_vertex_layout, vertex_base, vertex_count);
    m_geometry_packet.persistent_vertex_bytes.resize(required.first);
    m_geometry_packet.transient_vertex_bytes.resize(required.second);
    m_draw_processor.write_vertex_data_to_memory(
        m_vertex_layout,
        vertex_base,
        vertex_count,
        m_geometry_packet.persistent_vertex_bytes.empty()
            ? nullptr
            : m_geometry_packet.persistent_vertex_bytes.data(),
        m_geometry_packet.transient_vertex_bytes.empty()
            ? nullptr
            : m_geometry_packet.transient_vertex_bytes.data());

    auto& parameters = m_geometry_packet.draw_parameters;
    parameters.vertex_base_index = vertex_index_base;
    parameters.vertex_index_offset = vertex_index_offset;
    parameters.draw_id = 0;
    parameters.xform_constants_offset = 0;
    parameters.vs_context_offset = 0;
    parameters.fs_constants_offset = 0;
    parameters.fs_context_offset = 0;
    parameters.fs_texture_base_index = 0;
    parameters.fs_stipple_pattern_offset = 0;

    m_draw_processor.fill_vertex_layout_state(
        m_vertex_layout,
        current_vp_metadata,
        vertex_base,
        vertex_count,
        parameters.attrib_data.data(),
        0,
        0);

    auto& context = m_geometry_packet.vertex_context;
    m_draw_processor.fill_scale_offset_data(context.scale_offset_matrix.data(), false);
    m_draw_processor.fill_user_clip_data(&context.user_clip_configuration_bits);
    context.transform_branch_bits = rsx::method_registers.transform_branch_bits();
    context.point_size = rsx::method_registers.point_size() * rsx::get_resolution_scale();
    context.z_near = rsx::method_registers.clip_min();
    context.z_far = rsx::method_registers.clip_max();

    m_geometry_packet.gcm_primitive = gcm_primitive;
    m_geometry_packet.vertex_base = vertex_base;
    m_geometry_packet.vertex_count = vertex_count;
    m_geometry_packet.draw_count = draw_count;
    m_geometry_packet.min_index = min_index;
    m_geometry_packet.max_index = max_index;
    m_geometry_packet.vertex_index_base = vertex_index_base;
    m_geometry_packet.vertex_index_offset = vertex_index_offset;
    m_geometry_packet.persistent_byte_count = required.first;
    m_geometry_packet.transient_byte_count = required.second;
    m_geometry_packet.attribute_mask = m_vertex_layout.attribute_mask;
    m_geometry_packet.referenced_input_mask = current_vp_metadata.referenced_inputs_mask;
    m_geometry_packet.index_format = index_format;
    m_geometry_packet.indexed = indexed;
    m_geometry_packet.topology_rewritten = topology_rewritten;
    m_geometry_packet.primitive_restart_present = primitive_restart_present;
    m_geometry_packet.valid = true;

    std::string error;
    if (!metal_rsx::validate_geometry_packet(m_geometry_packet, error))
    {
        ++m_geometry_failures;
        m_geometry_packet.clear();
        m_last_geometry_error = std::move(error);
        return false;
    }

    ++m_geometry_ready_draws;
    m_last_geometry_error.clear();
    return true;
}

bool metal_gs_render::bind_live_frame_resources()
{
    if (!m_backend.frame_active())
    {
        std::string error;
        if (!m_backend.begin_frame(0.0f, 0.0f, 0.0f, 1.0f, error))
        {
            ++m_resource_binding_failures;
            m_last_binding_error = std::move(error);
            return false;
        }
    }

    std::string error;
    if (!m_backend.bind_render_pipeline(m_active_pipeline, error))
    {
        ++m_resource_binding_failures;
        m_last_binding_error = std::move(error);
        return false;
    }
    if (!m_backend.upload_and_bind_vertex_resources(m_geometry_packet, m_vertex_bindings, error))
    {
        ++m_resource_binding_failures;
        m_last_binding_error = std::move(error);
        return false;
    }

    m_frame_has_live_resources = true;
    ++m_resource_bound_draws;
    m_last_binding_error.clear();
    return true;
}

void metal_gs_render::flip(const rsx::display_flip_info_t& info)
{
    if (initialize_backend())
    {
        std::string error;
        if (m_backend.frame_active())
        {
            if (m_backend.end_frame(error))
            {
                ++m_presented_frames;
                m_frame_has_live_resources = false;
            }
            else
            {
                m_last_binding_error = std::move(error);
            }
        }
        else if (m_backend.present_test_frame(0.0f, 0.0f, 0.0f, 1.0f, error))
        {
            ++m_presented_frames;
        }
    }

    GSRender::flip(info);
}

void metal_gs_render::end()
{
    // Resolve live RPCS3 programs, validate post-SPIRV-Cross Metal bindings,
    // convert the live RSX vertex/index data, and bind those real resources into
    // the frame encoder. Guest geometry submission remains disabled until the
    // vertex constants and complete fragment resource set are connected.
    analyse_current_rsx_pipeline();
    capture_rsx_draw_state();
    const bool program_ready = prepare_live_program_pipeline();
    const bool geometry_ready = prepare_live_geometry_packet();
    if (program_ready && geometry_ready)
        bind_live_frame_resources();
    execute_nop_draw();
    rsx::thread::end();
}
} // namespace rpcs3::ios::render
