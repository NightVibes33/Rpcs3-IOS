#pragma once

#include "RPCS3MetalVertexEnvironment.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace rpcs3::ios::render::metal_rsx
{
enum class geometry_index_format : std::uint8_t
{
    none = 0,
    uint16,
    uint32,
};

/*
 * Host-side snapshot of one live RPCS3 draw after RPCS3's existing vertex and
 * index conversion helpers have processed RSX memory. This object deliberately
 * stops before Metal resource binding: the generated MSL binding table must be
 * connected before these bytes can be submitted as guest geometry.
 */
struct geometry_packet
{
    std::vector<std::byte> persistent_vertex_bytes;
    std::vector<std::byte> transient_vertex_bytes;
    std::vector<std::byte> index_bytes;

    vertex_context_record vertex_context{};
    draw_parameters_record draw_parameters{};

    std::uint32_t gcm_primitive = 0;
    std::uint32_t vertex_base = 0;
    std::uint32_t vertex_count = 0;
    std::uint32_t draw_count = 0;
    std::uint32_t min_index = 0;
    std::uint32_t max_index = 0;
    std::uint32_t vertex_index_base = 0;
    std::uint32_t vertex_index_offset = 0;
    std::uint32_t persistent_byte_count = 0;
    std::uint32_t transient_byte_count = 0;
    std::uint16_t attribute_mask = 0;
    std::uint16_t referenced_input_mask = 0;
    geometry_index_format index_format = geometry_index_format::none;

    bool indexed = false;
    bool topology_rewritten = false;
    bool primitive_restart_present = false;
    bool valid = false;

    void clear() noexcept;
    [[nodiscard]] std::size_t total_vertex_bytes() const noexcept;
    [[nodiscard]] std::size_t total_bytes() const noexcept;
};

bool validate_geometry_packet(const geometry_packet& packet, std::string& error);
} // namespace rpcs3::ios::render::metal_rsx
