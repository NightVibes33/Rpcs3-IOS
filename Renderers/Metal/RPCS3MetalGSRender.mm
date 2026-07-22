#include "RPCS3MetalGSRender.h"

#include "Emu/RSX/rsx_methods.h"
#include "Utilities/Thread.h"

#import <Metal/Metal.h>

#include <algorithm>
#include <cmath>
#include <string>

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

    std::string shader_error;
    m_shader_frontend_initialized = m_shader_frontend.initialize(shader_error);
    if (!m_shader_frontend_initialized)
        rsx_log.error("Native Metal could not initialize RPCS3's live shader frontend: %s", shader_error);

    initialize_backend();
}

void metal_gs_render::on_exit()
{
    m_shader_frontend.shutdown();
    m_shader_frontend_initialized = false;
    m_backend.shutdown();
    m_backend_initialized = false;
    GSRender::on_exit();
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
        rsx_log.error("Native Metal backend initialization failed: %s", error);
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

bool metal_gs_render::prepare_current_shader_pipeline(std::string& error)
{
    if (!m_shader_frontend_initialized || !initialize_backend())
    {
        error = "Native Metal shader or renderer frontend is not initialized.";
        return false;
    }

    if (!m_shader_frontend.compile_vertex(
            current_vertex_program, m_vertex_frontend_shader, error))
        return false;
    if (!m_shader_frontend.compile_fragment(
            current_fragment_program, m_fragment_frontend_shader, error))
        return false;

    if (!m_backend.compile_spirv_shader(
            m_vertex_frontend_shader.spirv,
            metal_rsx::shader_stage::vertex,
            m_vertex_shader,
            error))
        return false;
    if (!m_backend.compile_spirv_shader(
            m_fragment_frontend_shader.spirv,
            metal_rsx::shader_stage::fragment,
            m_fragment_shader,
            error))
        return false;

    metal_rsx::render_pipeline_request request;
    request.vertex_function = m_vertex_shader.function;
    request.fragment_function = m_fragment_shader.function;
    request.color_pixel_format = static_cast<std::uint32_t>(MTLPixelFormatBGRA8Unorm);
    request.depth_pixel_format = static_cast<std::uint32_t>(MTLPixelFormatInvalid);
    request.stencil_pixel_format = static_cast<std::uint32_t>(MTLPixelFormatInvalid);
    request.sample_count = 1;
    request.color_blend = m_color_blend_state;

    if (!m_backend.get_or_create_render_pipeline(request, m_render_pipeline, error))
        return false;

    ++m_compiled_program_pairs;
    error.clear();
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
    if (skip_current_frame ||
        rsx::method_registers.current_draw_clause.get_elements_count() == 0)
    {
        execute_nop_draw();
        rsx::thread::end();
        return;
    }

    capture_rsx_draw_state();
    analyse_current_rsx_pipeline();

    std::string shader_error;
    if (!prepare_current_shader_pipeline(shader_error))
        rsx_log.error("Native Metal live RSX shader/pipeline preparation failed: %s", shader_error);

    /* The live RSX programs now pass through RPCS3's real decompiler, SPIR-V,
     * SPIRV-Cross MSL translation, MTLLibrary compilation, and render-pipeline
     * cache. Geometry upload and binding the captured resource manifest are the
     * remaining requirements before this method may emit a guest draw. */
    execute_nop_draw();
    rsx::thread::end();
}
} // namespace rpcs3::ios::render
