#include "RPCS3MetalGSRender.h"

#include "Utilities/Thread.h"

#include <algorithm>
#include <cmath>
#include <string>

namespace rpcs3::ios::render
{
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

void metal_gs_render::flip(const rsx::display_flip_info_t& info)
{
    if (initialize_backend())
    {
        const double phase = static_cast<double>(m_presented_frames) / 90.0;
        const float red = static_cast<float>(0.05 + 0.05 * (std::sin(phase) + 1.0));
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
    /* The native Metal command queue and presentation path are active here.
     * RSX draw-state, shader, texture, and synchronization translation is added
     * incrementally; until then consume the method stream without fabricating
     * rendered geometry. */
    execute_nop_draw();
    rsx::thread::end();
}
} // namespace rpcs3::ios::render
