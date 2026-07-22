#include "RPCS3MetalPrimitiveExpander.h"

#include <algorithm>
#include <numeric>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
constexpr std::uint32_t gcm_points = 1;
constexpr std::uint32_t gcm_lines = 2;
constexpr std::uint32_t gcm_line_loop = 3;
constexpr std::uint32_t gcm_line_strip = 4;
constexpr std::uint32_t gcm_triangles = 5;
constexpr std::uint32_t gcm_triangle_strip = 6;
constexpr std::uint32_t gcm_triangle_fan = 7;
constexpr std::uint32_t gcm_quads = 8;
constexpr std::uint32_t gcm_quad_strip = 9;
constexpr std::uint32_t gcm_polygon = 10;

std::vector<std::uint32_t> copy_indices(std::span<const std::uint32_t> source)
{
    return {source.begin(), source.end()};
}

std::vector<std::uint32_t> expand_line_loop(std::span<const std::uint32_t> source)
{
    if (source.size() < 2)
        return copy_indices(source);

    std::vector<std::uint32_t> result;
    result.reserve(source.size() + 1);
    result.insert(result.end(), source.begin(), source.end());
    result.push_back(source.front());
    return result;
}

std::vector<std::uint32_t> expand_triangle_fan(std::span<const std::uint32_t> source)
{
    if (source.size() < 3)
        return {};

    std::vector<std::uint32_t> result;
    result.reserve((source.size() - 2) * 3);
    const std::uint32_t center = source.front();
    for (std::size_t index = 1; index + 1 < source.size(); ++index)
    {
        result.push_back(center);
        result.push_back(source[index]);
        result.push_back(source[index + 1]);
    }
    return result;
}

std::vector<std::uint32_t> expand_quads(std::span<const std::uint32_t> source)
{
    const std::size_t quad_count = source.size() / 4;
    std::vector<std::uint32_t> result;
    result.reserve(quad_count * 6);
    for (std::size_t quad = 0; quad < quad_count; ++quad)
    {
        const std::size_t base = quad * 4;
        const auto a = source[base + 0];
        const auto b = source[base + 1];
        const auto c = source[base + 2];
        const auto d = source[base + 3];
        result.insert(result.end(), {a, b, c, a, c, d});
    }
    return result;
}

std::vector<std::uint32_t> expand_quad_strip(std::span<const std::uint32_t> source)
{
    if (source.size() < 4)
        return {};

    const std::size_t quad_count = (source.size() - 2) / 2;
    std::vector<std::uint32_t> result;
    result.reserve(quad_count * 6);
    for (std::size_t quad = 0; quad < quad_count; ++quad)
    {
        const std::size_t base = quad * 2;
        const auto a = source[base + 0];
        const auto b = source[base + 1];
        const auto c = source[base + 2];
        const auto d = source[base + 3];
        result.insert(result.end(), {a, b, c, c, b, d});
    }
    return result;
}
} // namespace

bool primitive_requires_index_expansion(std::uint32_t primitive) noexcept
{
    switch (primitive)
    {
    case gcm_line_loop:
    case gcm_triangle_fan:
    case gcm_quads:
    case gcm_quad_strip:
    case gcm_polygon:
        return true;
    default:
        return false;
    }
}

std::vector<std::uint32_t> expand_primitive_indices(
    std::uint32_t primitive,
    std::span<const std::uint32_t> source)
{
    switch (primitive)
    {
    case gcm_points:
    case gcm_lines:
    case gcm_line_strip:
    case gcm_triangles:
    case gcm_triangle_strip:
        return copy_indices(source);
    case gcm_line_loop:
        return expand_line_loop(source);
    case gcm_triangle_fan:
    case gcm_polygon:
        return expand_triangle_fan(source);
    case gcm_quads:
        return expand_quads(source);
    case gcm_quad_strip:
        return expand_quad_strip(source);
    default:
        return {};
    }
}

std::vector<std::uint32_t> make_and_expand_sequential_indices(
    std::uint32_t primitive,
    std::size_t vertex_count)
{
    std::vector<std::uint32_t> source(vertex_count);
    std::iota(source.begin(), source.end(), 0u);
    return expand_primitive_indices(primitive, source);
}
} // namespace rpcs3::ios::render::metal_rsx
