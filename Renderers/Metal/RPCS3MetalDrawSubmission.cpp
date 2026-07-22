#include "RPCS3MetalDrawSubmission.h"

#include <limits>

namespace rpcs3::ios::render::metal_rsx
{
bool validate_draw_submission(
    const draw_submission& submission,
    std::string& error) noexcept
{
    if (!submission.render_pipeline_state)
    {
        error = "Metal draw submission has no render pipeline state.";
        return false;
    }

    if (submission.primitive_type > 4)
    {
        error = "Metal draw submission contains an unsupported primitive type.";
        return false;
    }

    if (submission.instance_count == 0)
    {
        error = "Metal draw submission has zero instances.";
        return false;
    }

    if (!submission.vertex_buffer.bytes || submission.vertex_buffer.byte_count == 0)
    {
        error = "Metal draw submission has no translated vertex data.";
        return false;
    }

    if (!submission.indexed())
    {
        if (submission.vertex_count == 0)
        {
            error = "Metal non-indexed draw submission has zero vertices.";
            return false;
        }

        error.clear();
        return true;
    }

    if (submission.index_count == 0)
    {
        error = "Metal indexed draw submission has zero indices.";
        return false;
    }

    if (!submission.index_buffer.bytes)
    {
        error = "Metal indexed draw submission has no index data.";
        return false;
    }

    const std::size_t index_size = submission.indices == index_format::uint16
        ? sizeof(std::uint16_t)
        : sizeof(std::uint32_t);

    if (submission.index_count > std::numeric_limits<std::size_t>::max() / index_size)
    {
        error = "Metal index buffer size overflow.";
        return false;
    }

    const std::size_t required_bytes = static_cast<std::size_t>(submission.index_count) * index_size;
    if (submission.index_buffer.byte_count < required_bytes)
    {
        error = "Metal index buffer is smaller than the translated index count.";
        return false;
    }

    error.clear();
    return true;
}
} // namespace rpcs3::ios::render::metal_rsx
