#pragma once

#include "RPCS3MetalDrawSubmission.h"

#include <string>

namespace rpcs3::ios::render::metal_rsx
{
// Uploads and binds the reflected resources carried by a draw_submission to
// an active MTLRenderCommandEncoder. The opaque handles keep this header valid
// C++ while the Objective-C++ implementation owns all Metal API interaction.
[[nodiscard]] bool bind_draw_resources(void* metal_device,
                                       void* render_command_encoder,
                                       const draw_submission& submission,
                                       std::string& error);
} // namespace rpcs3::ios::render::metal_rsx
