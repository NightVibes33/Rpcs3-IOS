#include "RPCS3MetalResourceBinder.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <cstddef>
#include <string>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
void bind_buffer(id<MTLRenderCommandEncoder> encoder,
                 resource_stage stage,
                 id<MTLBuffer> buffer,
                 std::uint32_t index)
{
    if (stage == resource_stage::vertex)
        [encoder setVertexBuffer:buffer offset:0 atIndex:index];
    else
        [encoder setFragmentBuffer:buffer offset:0 atIndex:index];
}

void bind_texture(id<MTLRenderCommandEncoder> encoder,
                  resource_stage stage,
                  id<MTLTexture> texture,
                  std::uint32_t index)
{
    if (stage == resource_stage::vertex)
        [encoder setVertexTexture:texture atIndex:index];
    else
        [encoder setFragmentTexture:texture atIndex:index];
}

void bind_sampler(id<MTLRenderCommandEncoder> encoder,
                  resource_stage stage,
                  id<MTLSamplerState> sampler,
                  std::uint32_t index)
{
    if (stage == resource_stage::vertex)
        [encoder setVertexSamplerState:sampler atIndex:index];
    else
        [encoder setFragmentSamplerState:sampler atIndex:index];
}

id<MTLBuffer> upload_buffer(id<MTLDevice> device,
                            const buffer_upload& upload,
                            const char* label,
                            std::string& error)
{
    id<MTLBuffer> buffer = [device newBufferWithBytes:upload.bytes
                                               length:upload.byte_count
                                              options:MTLResourceStorageModeShared];
    if (!buffer)
        error = std::string("Metal could not upload ") + label + ".";
    return buffer;
}
} // namespace

bool bind_draw_resources(void* metal_device,
                         void* render_command_encoder,
                         const draw_submission& submission,
                         std::string& error)
{
    id<MTLDevice> device = metal_device ? (__bridge id<MTLDevice>)metal_device : nil;
    id<MTLRenderCommandEncoder> encoder = render_command_encoder
        ? (__bridge id<MTLRenderCommandEncoder>)render_command_encoder
        : nil;
    if (!device || !encoder)
    {
        error = "Metal resource binding requires a valid device and active render encoder.";
        return false;
    }

    @autoreleasepool
    {
        // Keeps uploaded resources strongly referenced for the duration of the
        // binding call. Metal command encoders retain bound resources until the
        // command buffer completes.
        NSMutableArray* retained_resources = [NSMutableArray array];

        if (submission.vertex_buffer.bytes && submission.vertex_buffer.byte_count)
        {
            id<MTLBuffer> legacy_vertex = upload_buffer(
                device,
                submission.vertex_buffer,
                "the compatibility vertex buffer",
                error);
            if (!legacy_vertex)
                return false;
            [retained_resources addObject:legacy_vertex];
            [encoder setVertexBuffer:legacy_vertex offset:0 atIndex:0];
        }

        for (const auto& binding : submission.buffers)
        {
            id<MTLBuffer> buffer = upload_buffer(device, binding.upload, "a reflected shader buffer", error);
            if (!buffer)
                return false;
            [retained_resources addObject:buffer];
            bind_buffer(encoder, binding.stage, buffer, binding.index);
        }

        for (const auto& binding : submission.texture_buffers)
        {
            id<MTLBuffer> buffer = upload_buffer(device, binding.upload, "a reflected texture buffer", error);
            if (!buffer)
                return false;

            const NSUInteger texel_count = binding.upload.byte_count / binding.bytes_per_texel;
            if (!texel_count)
            {
                error = "Metal reflected texture buffer contains zero texels.";
                return false;
            }

            MTLTextureDescriptor* descriptor =
                [MTLTextureDescriptor textureBufferDescriptorWithPixelFormat:
                    static_cast<MTLPixelFormat>(binding.pixel_format)
                                                               width:texel_count
                                                     resourceOptions:MTLResourceStorageModeShared
                                                               usage:MTLTextureUsageShaderRead];
            if (!descriptor)
            {
                error = "Metal could not describe a reflected texture buffer.";
                return false;
            }

            id<MTLTexture> texture = [buffer newTextureWithDescriptor:descriptor
                                                               offset:0
                                                          bytesPerRow:binding.upload.byte_count];
            if (!texture)
            {
                error = "Metal could not create a texture view for a reflected RPCS3 buffer.";
                return false;
            }

            [retained_resources addObject:buffer];
            [retained_resources addObject:texture];
            bind_texture(encoder, binding.stage, texture, binding.index);
        }

        for (const auto& binding : submission.textures)
        {
            id<MTLTexture> texture = binding.texture
                ? (__bridge id<MTLTexture>)binding.texture
                : nil;
            if (!texture)
            {
                error = "Metal reflected texture binding contains no native texture.";
                return false;
            }
            [retained_resources addObject:texture];
            bind_texture(encoder, binding.stage, texture, binding.index);
        }

        for (const auto& binding : submission.samplers)
        {
            id<MTLSamplerState> sampler = binding.sampler
                ? (__bridge id<MTLSamplerState>)binding.sampler
                : nil;
            if (!sampler)
            {
                error = "Metal reflected sampler binding contains no native sampler.";
                return false;
            }
            [retained_resources addObject:sampler];
            bind_sampler(encoder, binding.stage, sampler, binding.index);
        }

        error.clear();
        return true;
    }
}
} // namespace rpcs3::ios::render::metal_rsx
