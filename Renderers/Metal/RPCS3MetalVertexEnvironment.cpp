#include "RPCS3MetalVertexEnvironment.h"

#include <cmath>

namespace rpcs3::ios::render::metal_rsx
{
bool validate_vertex_environment(const vertex_context_record& context,
                                 const draw_parameters_record& parameters,
                                 std::string& error)
{
    for (const float value : context.scale_offset_matrix)
    {
        if (!std::isfinite(value))
        {
            error = "RPCS3 Metal vertex context contains a non-finite scale/offset matrix value.";
            return false;
        }
    }
    if (!std::isfinite(context.point_size) || context.point_size < 0.0f)
    {
        error = "RPCS3 Metal vertex context contains an invalid point size.";
        return false;
    }
    if (!std::isfinite(context.z_near) || !std::isfinite(context.z_far))
    {
        error = "RPCS3 Metal vertex context contains a non-finite clip range.";
        return false;
    }
    if (parameters.vs_context_offset != 0)
    {
        error = "Single-draw Metal packets currently require vertex context offset zero.";
        return false;
    }
    if (parameters.draw_id != 0)
    {
        error = "Single-draw Metal packets currently require draw id zero.";
        return false;
    }

    error.clear();
    return true;
}
} // namespace rpcs3::ios::render::metal_rsx
