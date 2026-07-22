#include "RPCS3MetalDrawSubmission.h"

#include <limits>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
bool validate_upload(const buffer_upload& upload, const char* label, std::string& error)
{
    if (!upload.bytes || upload.byte_count == 0)
    {
        error = std::string("Metal draw submission has an empty ") + label + ".";
        return false;
    }
    return true;
}

bool validate_binding_index(std::uint32_t index, const char* label, std::string& error)
{
    // Metal's exact per-stage limits vary by device family. Reject obviously
    // invalid reflected indices here and let the native API enforce the
    // device-specific maximum during encoding.
    if (index == UINT32_MAX || index > 1023)
    {
        error = std::string("Metal draw submission has an invalid ") + label + " index.";
        return false;
    }
    return true;
}
} // namespace

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

    if (!submission.has_vertex_resources())
    {
        error = "Metal draw submission has no translated vertex resources.";
        return false;
    }

    for (const auto& binding : submission.buffers)
    {
        if (!validate_binding_index(binding.index, "buffer binding", error) ||
            !validate_upload(binding.upload, "buffer binding", error))
            return false;
    }

    for (const auto& binding : submission.texture_buffers)
    {
        if (!validate_binding_index(binding.index, "texture-buffer binding", error) ||
            !validate_upload(binding.upload, "texture-buffer binding", error))
            return false;
        if (!binding.pixel_format || !binding.bytes_per_texel)
        {
            error = "Metal texture-buffer binding has no pixel format or texel size.";
            return false;
        }
        if (binding.upload.byte_count % binding.bytes_per_texel)
        {
            error = "Metal texture-buffer byte count is not aligned to its texel size.";
            return false;
        }
    }

    for (const auto& binding : submission.textures)
    {
        if (!validate_binding_index(binding.index, "texture binding", error) || !binding.texture)
        {
            if (error.empty())
                error = "Metal texture binding has no texture.";
            return false;
        }
    }

    for (const auto& binding : submission.samplers)
    {
        if (!validate_binding_index(binding.index, "sampler binding", error) || !binding.sampler)
        {
            if (error.empty())
                error = "Metal sampler binding has no sampler.";
            return false;
        }
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
