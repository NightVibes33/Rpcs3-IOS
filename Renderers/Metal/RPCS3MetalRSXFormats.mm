#include "RPCS3MetalRSXFormats.h"

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
constexpr std::uint32_t texture_linear_bit = 0x20;
constexpr std::uint32_t texture_unnormalized_bit = 0x40;

constexpr std::uint32_t texture_base(std::uint32_t value) noexcept
{
    return value & ~(texture_linear_bit | texture_unnormalized_bit);
}
} // namespace

primitive_mapping map_primitive(std::uint32_t value) noexcept
{
    // CELL_GCM_PRIMITIVE_*
    switch (value)
    {
    case 1: return {MTLPrimitiveTypePoint, false};
    case 2: return {MTLPrimitiveTypeLine, false};
    case 3: return {MTLPrimitiveTypeLineStrip, true};   // close the loop with one generated index
    case 4: return {MTLPrimitiveTypeLineStrip, false};
    case 5: return {MTLPrimitiveTypeTriangle, false};
    case 6: return {MTLPrimitiveTypeTriangleStrip, false};
    case 7: return {MTLPrimitiveTypeTriangle, true};    // triangle fan expansion
    case 8: return {MTLPrimitiveTypeTriangle, true};    // quad expansion
    case 9: return {MTLPrimitiveTypeTriangle, true};    // quad-strip expansion
    case 10: return {MTLPrimitiveTypeTriangle, true};   // polygon fan expansion
    default: return {MTLPrimitiveTypeTriangle, true};
    }
}

MTLCompareFunction map_compare_function(std::uint32_t value) noexcept
{
    switch (value)
    {
    case 0x0200: return MTLCompareFunctionNever;
    case 0x0201: return MTLCompareFunctionLess;
    case 0x0202: return MTLCompareFunctionEqual;
    case 0x0203: return MTLCompareFunctionLessEqual;
    case 0x0204: return MTLCompareFunctionGreater;
    case 0x0205: return MTLCompareFunctionNotEqual;
    case 0x0206: return MTLCompareFunctionGreaterEqual;
    case 0x0207: return MTLCompareFunctionAlways;
    default: return MTLCompareFunctionAlways;
    }
}

MTLStencilOperation map_stencil_operation(std::uint32_t value) noexcept
{
    switch (value)
    {
    case 0x0000: return MTLStencilOperationZero;
    case 0x150A: return MTLStencilOperationInvert;
    case 0x1E00: return MTLStencilOperationKeep;
    case 0x1E01: return MTLStencilOperationReplace;
    case 0x1E02: return MTLStencilOperationIncrementClamp;
    case 0x1E03: return MTLStencilOperationDecrementClamp;
    case 0x8507: return MTLStencilOperationIncrementWrap;
    case 0x8508: return MTLStencilOperationDecrementWrap;
    default: return MTLStencilOperationKeep;
    }
}

MTLBlendOperation map_blend_operation(std::uint32_t value) noexcept
{
    switch (value)
    {
    case 0x8006: return MTLBlendOperationAdd;
    case 0x8007: return MTLBlendOperationMin;
    case 0x8008: return MTLBlendOperationMax;
    case 0x800A: return MTLBlendOperationSubtract;
    case 0x800B: return MTLBlendOperationReverseSubtract;
    // Signed NV blend equations need shader-side emulation. Add is the least
    // destructive hardware fallback while the pipeline marks them unsupported.
    case 0x0000F005:
    case 0x0000F006:
    case 0x0000F007:
    default:
        return MTLBlendOperationAdd;
    }
}

MTLBlendFactor map_blend_factor(std::uint32_t value) noexcept
{
    switch (value)
    {
    case 0x0000: return MTLBlendFactorZero;
    case 0x0001: return MTLBlendFactorOne;
    case 0x0300: return MTLBlendFactorSourceColor;
    case 0x0301: return MTLBlendFactorOneMinusSourceColor;
    case 0x0302: return MTLBlendFactorSourceAlpha;
    case 0x0303: return MTLBlendFactorOneMinusSourceAlpha;
    case 0x0304: return MTLBlendFactorDestinationAlpha;
    case 0x0305: return MTLBlendFactorOneMinusDestinationAlpha;
    case 0x0306: return MTLBlendFactorDestinationColor;
    case 0x0307: return MTLBlendFactorOneMinusDestinationColor;
    case 0x0308: return MTLBlendFactorSourceAlphaSaturated;
    case 0x8001: return MTLBlendFactorBlendColor;
    case 0x8002: return MTLBlendFactorOneMinusBlendColor;
    case 0x8003: return MTLBlendFactorBlendAlpha;
    case 0x8004: return MTLBlendFactorOneMinusBlendAlpha;
    default: return MTLBlendFactorOne;
    }
}

MTLColorWriteMask map_color_write_mask(std::uint32_t value) noexcept
{
    MTLColorWriteMask result = MTLColorWriteMaskNone;
    if (value & (1u << 16)) result |= MTLColorWriteMaskRed;
    if (value & (1u << 8)) result |= MTLColorWriteMaskGreen;
    if (value & (1u << 0)) result |= MTLColorWriteMaskBlue;
    if (value & (1u << 24)) result |= MTLColorWriteMaskAlpha;
    return result;
}

pixel_format_mapping map_texture_format(std::uint32_t value, bool srgb) noexcept
{
    switch (texture_base(value))
    {
    case 0x81: return {MTLPixelFormatR8Unorm, false, false, false};
    case 0x82: return {MTLPixelFormatBGR5A1Unorm, false, false, false};
    case 0x83: return {MTLPixelFormatABGR4Unorm, false, false, false};
    case 0x84: return {MTLPixelFormatB5G6R5Unorm, false, false, false};
    case 0x85: return {srgb ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm, false, false, false};
    case 0x86: return {MTLPixelFormatInvalid, true, false, false}; // DXT1/BC1: decode or transcode on iOS
    case 0x87: return {MTLPixelFormatInvalid, true, false, false}; // DXT2/3/BC2
    case 0x88: return {MTLPixelFormatInvalid, true, false, false}; // DXT4/5/BC3
    case 0x8B: return {MTLPixelFormatRG8Unorm, false, false, false};
    case 0x8D:
    case 0x8E: return {MTLPixelFormatBGRA8Unorm, true, false, false};
    case 0x8F: return {MTLPixelFormatB5G6R5Unorm, true, false, false};
    case 0x90:
    case 0x91: return {MTLPixelFormatDepth32Float_Stencil8, true, true, true};
    case 0x92: return {MTLPixelFormatDepth16Unorm, false, true, false};
    case 0x93: return {MTLPixelFormatDepth32Float, true, true, false};
    case 0x94: return {MTLPixelFormatR16Unorm, false, false, false};
    case 0x95: return {MTLPixelFormatRG16Unorm, false, false, false};
    case 0x97: return {MTLPixelFormatBGR5A1Unorm, true, false, false};
    case 0x98: return {MTLPixelFormatRG8Unorm, false, false, false};
    case 0x99: return {MTLPixelFormatRG8Snorm, false, false, false};
    case 0x9A: return {MTLPixelFormatRGBA16Float, false, false, false};
    case 0x9B: return {MTLPixelFormatRGBA32Float, false, false, false};
    case 0x9C: return {MTLPixelFormatR32Float, false, false, false};
    case 0x9D: return {MTLPixelFormatBGR5A1Unorm, true, false, false};
    case 0x9E: return {srgb ? MTLPixelFormatBGRA8Unorm_sRGB : MTLPixelFormatBGRA8Unorm, true, false, false};
    case 0x9F: return {MTLPixelFormatRG16Float, false, false, false};
    default: return {MTLPixelFormatInvalid, true, false, false};
    }
}

pixel_format_mapping map_depth_format(std::uint32_t value) noexcept
{
    // CELL_GCM_SURFACE_Z16 and CELL_GCM_SURFACE_Z24S8 are encoded as 1 and 2.
    switch (value)
    {
    case 1: return {MTLPixelFormatDepth16Unorm, false, true, false};
    case 2: return {MTLPixelFormatDepth32Float_Stencil8, true, true, true};
    default: return {MTLPixelFormatInvalid, true, true, false};
    }
}
} // namespace rpcs3::ios::render::metal_rsx
