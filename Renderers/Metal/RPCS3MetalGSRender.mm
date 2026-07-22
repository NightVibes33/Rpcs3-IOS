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
    /* Decode the active RSX primitive, depth/stencil, blend, and write-mask
     * registers into real Metal descriptors for every draw. Vertex/index
     * upload, shader translation, texture binding, and actual draw encoding are
     * the remaining stages; until those land, consume the method stream without
     * claiming rendered guest geometry. */
    capture_rsx_draw_state();
    execute_nop_draw();
    rsx::thread::end();
}
} // namespace rpcs3::ios::render
