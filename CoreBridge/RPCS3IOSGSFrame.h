#pragma once

#include "Emu/RSX/GSFrameBase.h"

#include <memory>

namespace rpcs3::ios
{
// QWidget::winId() is a UIView* on iOS. A runtime-owned CAMetalLayer-backed
// child view is attached to it and returned to RPCS3 as the Apple display handle.
bool attach_render_view(void* native_view);
void detach_render_view();
bool render_view_ready();
std::unique_ptr<GSFrameBase> make_gs_frame();
} // namespace rpcs3::ios
