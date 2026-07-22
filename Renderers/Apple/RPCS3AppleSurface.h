#pragma once

#include <cstdint>
#include <string>

namespace rpcs3::ios::render
{
struct apple_surface;

/*
 * Sets the UIKit view that future RPCS3 GS frames should embed into. Qt's iOS
 * platform plugin exposes its native QWidget as a UIView through winId(). The
 * pointer is not retained; callers must clear it before the view is destroyed.
 */
void set_preferred_apple_surface_parent(void* native_view) noexcept;
void* preferred_apple_surface_parent() noexcept;

apple_surface* create_apple_metal_surface(void* native_parent_view,
                                          std::uint32_t pixel_width,
                                          std::uint32_t pixel_height,
                                          float content_scale,
                                          std::string& error);
void resize_apple_surface(apple_surface* surface,
                          std::uint32_t pixel_width,
                          std::uint32_t pixel_height,
                          float content_scale) noexcept;
void* apple_surface_layer(apple_surface* surface) noexcept;
void* apple_surface_view(apple_surface* surface) noexcept;
void destroy_apple_surface(apple_surface* surface) noexcept;
} // namespace rpcs3::ios::render
