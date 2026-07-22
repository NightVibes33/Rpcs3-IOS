#include "RPCS3IOSGSFrame.h"
#include "RPCS3AppleSurface.h"

#import <UIKit/UIKit.h>

#include <algorithm>
#include <utility>

namespace rpcs3::ios::render
{
ios_gs_frame::ios_gs_frame() = default;

ios_gs_frame::~ios_gs_frame()
{
    close();
}

bool ios_gs_frame::ensure_surface() const
{
    std::lock_guard lock(m_mutex);
    if (m_surface)
        return true;

    const float scale = static_cast<float>(std::max<CGFloat>(UIScreen.mainScreen.scale, 1.0));
    m_surface = create_apple_metal_surface(nullptr, m_width, m_height, scale, m_last_error);
    return m_surface != nullptr;
}

void ios_gs_frame::close()
{
    std::lock_guard lock(m_mutex);
    destroy_apple_surface(std::exchange(m_surface, nullptr));
    m_visible = false;
}

void ios_gs_frame::reset()
{
    if (!ensure_surface())
        return;
    std::lock_guard lock(m_mutex);
    resize_apple_surface(m_surface,
                         m_width,
                         m_height,
                         static_cast<float>(std::max<CGFloat>(UIScreen.mainScreen.scale, 1.0)));
}

bool ios_gs_frame::shown()
{
    return m_visible;
}

void ios_gs_frame::hide()
{
    m_visible = false;
}

void ios_gs_frame::show()
{
    m_visible = true;
    ensure_surface();
}

void ios_gs_frame::toggle_fullscreen()
{
    show();
}

void ios_gs_frame::delete_context(draw_context_t)
{
}

draw_context_t ios_gs_frame::make_context()
{
    return ensure_surface() ? apple_surface_layer(m_surface) : nullptr;
}

void ios_gs_frame::set_current(draw_context_t)
{
}

void ios_gs_frame::flip(draw_context_t, bool)
{
}

int ios_gs_frame::client_width()
{
    return static_cast<int>(m_width);
}

int ios_gs_frame::client_height()
{
    return static_cast<int>(m_height);
}

f64 ios_gs_frame::client_display_rate()
{
    const NSInteger rate = UIScreen.mainScreen.maximumFramesPerSecond;
    return rate > 0 ? static_cast<f64>(rate) : 60.0;
}

bool ios_gs_frame::has_alpha()
{
    return false;
}

display_handle_t ios_gs_frame::handle() const
{
    return ensure_surface() ? apple_surface_view(m_surface) : nullptr;
}

bool ios_gs_frame::can_consume_frame() const
{
    return false;
}

void ios_gs_frame::present_frame(std::vector<u8>&&, u32, u32, u32, bool) const
{
}

void ios_gs_frame::take_screenshot(std::vector<u8>&&, u32, u32, bool)
{
}

void ios_gs_frame::update_title(double)
{
}
} // namespace rpcs3::ios::render
