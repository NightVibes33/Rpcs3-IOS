#pragma once

#include <cstddef>
#include <cstdint>
#include <span>
#include <vector>

namespace rpcs3::ios::render::metal_rsx
{
bool primitive_requires_index_expansion(std::uint32_t gcm_primitive) noexcept;

/*
 * Converts RSX primitive topology into an index stream accepted by Metal.
 * Native Metal topologies are returned unchanged. Unsupported GCM topologies
 * are expanded while preserving their original vertex winding.
 */
std::vector<std::uint32_t> expand_primitive_indices(
    std::uint32_t gcm_primitive,
    std::span<const std::uint32_t> source_indices);

std::vector<std::uint32_t> make_and_expand_sequential_indices(
    std::uint32_t gcm_primitive,
    std::size_t vertex_count);
} // namespace rpcs3::ios::render::metal_rsx
