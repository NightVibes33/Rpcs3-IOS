#pragma once

#include "Emu/RSX/GSFrameBase.h"

#include <memory>

// Attaches a CAMetalLayer-backed child UIView to the native Qt iOS host UIView.
// The native handle is supplied by QWidget::winId(), which Qt maps to UIView* on iOS.
int rpcs3_ios_attach_metal_view(void* host_view, int pixel_width, int pixel_height, double refresh_rate);
void rpcs3_ios_update_metal_view_metrics(int pixel_width, int pixel_height, double refresh_rate);
bool rpcs3_ios_has_metal_view();
std::unique_ptr<GSFrameBase> rpcs3_ios_make_gs_frame();
