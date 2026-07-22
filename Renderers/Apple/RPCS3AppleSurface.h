#pragma once

#include <cstdint>
#include <string>

namespace rpcs3::ios::render
{
struct apple_surface;

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
