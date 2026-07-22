#include "RPCS3MetalResourceBindings.h"

namespace rpcs3::ios::render::metal_rsx
{
bool vertex_resource_bindings::complete() const noexcept
{
    return persistent_vertex_texture != invalid_metal_resource_index &&
        transient_vertex_texture != invalid_metal_resource_index &&
        draw_parameters_buffer != invalid_metal_resource_index &&
        vertex_context_buffer != invalid_metal_resource_index;
}

bool resolve_vertex_resource_bindings(
    const std::vector<shader_resource_binding>& resources,
    vertex_resource_bindings& output,
    std::string& error)
{
    output = {};

    for (const shader_resource_binding& resource : resources)
    {
        if (resource.kind == shader_resource_kind::push_constant)
        {
            output.push_constant_buffer = resource.metal_index;
            continue;
        }
        if (resource.descriptor_set != 0 || resource.metal_index == invalid_metal_resource_index)
            continue;

        switch (resource.descriptor_binding)
        {
        case 0:
            if (resource.kind == shader_resource_kind::sampled_image ||
                resource.kind == shader_resource_kind::separate_image)
            {
                output.persistent_vertex_texture = resource.metal_index;
            }
            break;
        case 1:
            if (resource.kind == shader_resource_kind::sampled_image ||
                resource.kind == shader_resource_kind::separate_image)
            {
                output.transient_vertex_texture = resource.metal_index;
            }
            break;
        case 2:
            if (resource.kind == shader_resource_kind::storage_buffer ||
                resource.kind == shader_resource_kind::uniform_buffer)
            {
                output.draw_parameters_buffer = resource.metal_index;
            }
            break;
        case 3:
            if (resource.kind == shader_resource_kind::storage_buffer ||
                resource.kind == shader_resource_kind::uniform_buffer)
            {
                output.vertex_context_buffer = resource.metal_index;
            }
            break;
        default:
            break;
        }
    }

    if (!output.complete())
    {
        error = "Translated RPCS3 vertex shader is missing one or more required Metal bindings "
            "for persistent vertices, transient vertices, draw parameters, or vertex context.";
        return false;
    }

    error.clear();
    return true;
}
} // namespace rpcs3::ios::render::metal_rsx
