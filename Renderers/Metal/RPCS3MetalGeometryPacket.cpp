#include "RPCS3MetalGeometryPacket.h"

namespace rpcs3::ios::render::metal_rsx
{
void geometry_packet::clear() noexcept
{
    persistent_vertex_bytes.clear();
    transient_vertex_bytes.clear();
    index_bytes.clear();
    vertex_context = {};
    draw_parameters = {};
    gcm_primitive = 0;
    vertex_base = 0;
    vertex_count = 0;
    draw_count = 0;
    min_index = 0;
    max_index = 0;
    vertex_index_base = 0;
    vertex_index_offset = 0;
    persistent_byte_count = 0;
    transient_byte_count = 0;
    attribute_mask = 0;
    referenced_input_mask = 0;
    index_format = geometry_index_format::none;
    indexed = false;
    topology_rewritten = false;
    primitive_restart_present = false;
    valid = false;
}

std::size_t geometry_packet::total_vertex_bytes() const noexcept
{
    return persistent_vertex_bytes.size() + transient_vertex_bytes.size();
}

std::size_t geometry_packet::total_bytes() const noexcept
{
    return total_vertex_bytes() + index_bytes.size();
}

bool validate_geometry_packet(const geometry_packet& packet, std::string& error)
{
    if (!packet.valid)
    {
        error = "Metal geometry packet is not marked valid.";
        return false;
    }
    if (packet.vertex_count == 0 || packet.draw_count == 0)
    {
        error = "Metal geometry packet contains an empty draw range.";
        return false;
    }
    if (packet.total_vertex_bytes() == 0)
    {
        error = "Metal geometry packet contains no converted RPCS3 vertex bytes.";
        return false;
    }
    if (packet.persistent_byte_count != packet.persistent_vertex_bytes.size() ||
        packet.transient_byte_count != packet.transient_vertex_bytes.size())
    {
        error = "Metal geometry packet byte counts do not match their storage.";
        return false;
    }
    if (packet.draw_parameters.vertex_base_index != packet.vertex_index_base ||
        packet.draw_parameters.vertex_index_offset != packet.vertex_index_offset)
    {
        error = "Metal geometry packet draw parameters do not match the converted index range.";
        return false;
    }
    if (!validate_vertex_environment(packet.vertex_context, packet.draw_parameters, error))
        return false;

    if (packet.indexed)
    {
        if (packet.index_format == geometry_index_format::none || packet.index_bytes.empty())
        {
            error = "Indexed Metal geometry packet is missing normalized index data.";
            return false;
        }
        const std::size_t index_size = packet.index_format == geometry_index_format::uint16
            ? sizeof(std::uint16_t)
            : sizeof(std::uint32_t);
        if (packet.index_bytes.size() < static_cast<std::size_t>(packet.draw_count) * index_size)
        {
            error = "Indexed Metal geometry packet is smaller than its draw count.";
            return false;
        }
    }
    else if (packet.index_format != geometry_index_format::none || !packet.index_bytes.empty())
    {
        error = "Non-indexed Metal geometry packet unexpectedly contains indices.";
        return false;
    }

    error.clear();
    return true;
}
} // namespace rpcs3::ios::render::metal_rsx
