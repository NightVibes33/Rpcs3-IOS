#pragma once

#include <memory>

class GSFrameBase;

namespace rpcs3::ios
{
// Attaches the runtime-owned CAMetalLayer to a native Qt iOS UIView.
// Qt maps QWidget::winId() to UIView* on iOS.
int attach_render_view(void* native_view);
void detach_render_view();
bool render_view_ready();

// Creates the GSFrameBase object consumed by RPCS3's real RSX renderers.
std::unique_ptr<GSFrameBase> make_gs_frame();
}
