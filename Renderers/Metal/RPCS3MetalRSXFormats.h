#pragma once

#include <cstdint>

#ifdef __OBJC__
#import <Metal/Metal.h>

namespace rpcs3::ios::render::metal_rsx
{
struct primitive_mapping
{
    MTLPrimitiveType primitive = MTLPrimitiveTypeTriangle;
    bool requires_index_rewrite = false;
};

struct pixel_format_mapping
{
    MTLPixelFormat format = MTLPixelFormatInvalid;
    bool requires_conversion = false;
    bool depth = false;
    bool stencil = false;
};

primitive_mapping map_primitive(std::uint32_t gcm_primitive) noexcept;
MTLCompareFunction map_compare_function(std::uint32_t gcm_function) noexcept;
MTLStencilOperation map_stencil_operation(std::uint32_t gcm_operation) noexcept;
MTLBlendOperation map_blend_operation(std::uint32_t gcm_equation) noexcept;
MTLBlendFactor map_blend_factor(std::uint32_t gcm_factor) noexcept;
MTLColorWriteMask map_color_write_mask(std::uint32_t gcm_mask) noexcept;
pixel_format_mapping map_texture_format(std::uint32_t gcm_format, bool srgb) noexcept;
pixel_format_mapping map_depth_format(std::uint32_t gcm_format) noexcept;
} // namespace rpcs3::ios::render::metal_rsx
#endif
