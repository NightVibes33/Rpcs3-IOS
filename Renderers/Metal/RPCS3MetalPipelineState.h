#pragma once

#include <cstdint>

namespace rpcs3::ios::render::metal_rsx
{
struct stencil_face_state
{
    std::uint32_t compare_function = 0x0207;
    std::uint32_t stencil_failure = 0x1E00;
    std::uint32_t depth_failure = 0x1E00;
    std::uint32_t depth_stencil_pass = 0x1E00;
    std::uint32_t read_mask = 0xff;
    std::uint32_t write_mask = 0xff;
};

struct depth_stencil_state
{
    bool depth_test_enabled = false;
    bool depth_write_enabled = false;
    std::uint32_t depth_compare_function = 0x0207;
    bool stencil_test_enabled = false;
    stencil_face_state front;
    stencil_face_state back;
};

struct color_blend_state
{
    bool blend_enabled = false;
    std::uint32_t source_rgb_factor = 1;
    std::uint32_t destination_rgb_factor = 0;
    std::uint32_t rgb_equation = 0x8006;
    std::uint32_t source_alpha_factor = 1;
    std::uint32_t destination_alpha_factor = 0;
    std::uint32_t alpha_equation = 0x8006;
    std::uint32_t color_write_mask = 0x01010101;
};
} // namespace rpcs3::ios::render::metal_rsx

#ifdef __OBJC__
#import <Metal/Metal.h>

namespace rpcs3::ios::render::metal_rsx
{
void configure_depth_stencil_descriptor(
    MTLDepthStencilDescriptor* descriptor,
    const depth_stencil_state& state);

void configure_color_attachment(
    MTLRenderPipelineColorAttachmentDescriptor* attachment,
    const color_blend_state& state);
} // namespace rpcs3::ios::render::metal_rsx
#endif
