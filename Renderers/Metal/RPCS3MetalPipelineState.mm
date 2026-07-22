#include "RPCS3MetalPipelineState.h"
#include "RPCS3MetalRSXFormats.h"

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
void configure_stencil_face(
    MTLStencilDescriptor* descriptor,
    const stencil_face_state& state)
{
    descriptor.stencilCompareFunction = map_compare_function(state.compare_function);
    descriptor.stencilFailureOperation = map_stencil_operation(state.stencil_failure);
    descriptor.depthFailureOperation = map_stencil_operation(state.depth_failure);
    descriptor.depthStencilPassOperation = map_stencil_operation(state.depth_stencil_pass);
    descriptor.readMask = state.read_mask;
    descriptor.writeMask = state.write_mask;
}
} // namespace

void configure_depth_stencil_descriptor(
    MTLDepthStencilDescriptor* descriptor,
    const depth_stencil_state& state)
{
    if (!descriptor)
        return;

    descriptor.depthCompareFunction = state.depth_test_enabled
        ? map_compare_function(state.depth_compare_function)
        : MTLCompareFunctionAlways;
    descriptor.depthWriteEnabled = state.depth_test_enabled && state.depth_write_enabled;

    if (!state.stencil_test_enabled)
    {
        descriptor.frontFaceStencil = nil;
        descriptor.backFaceStencil = nil;
        return;
    }

    MTLStencilDescriptor* front = [[MTLStencilDescriptor alloc] init];
    MTLStencilDescriptor* back = [[MTLStencilDescriptor alloc] init];
    configure_stencil_face(front, state.front);
    configure_stencil_face(back, state.back);
    descriptor.frontFaceStencil = front;
    descriptor.backFaceStencil = back;
}

void configure_color_attachment(
    MTLRenderPipelineColorAttachmentDescriptor* attachment,
    const color_blend_state& state)
{
    if (!attachment)
        return;

    attachment.writeMask = map_color_write_mask(state.color_write_mask);
    attachment.blendingEnabled = state.blend_enabled;
    if (!state.blend_enabled)
        return;

    attachment.sourceRGBBlendFactor = map_blend_factor(state.source_rgb_factor);
    attachment.destinationRGBBlendFactor = map_blend_factor(state.destination_rgb_factor);
    attachment.rgbBlendOperation = map_blend_operation(state.rgb_equation);
    attachment.sourceAlphaBlendFactor = map_blend_factor(state.source_alpha_factor);
    attachment.destinationAlphaBlendFactor = map_blend_factor(state.destination_alpha_factor);
    attachment.alphaBlendOperation = map_blend_operation(state.alpha_equation);
}
} // namespace rpcs3::ios::render::metal_rsx
