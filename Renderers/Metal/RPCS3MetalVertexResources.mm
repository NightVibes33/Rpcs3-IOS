#include "RPCS3MetalVertexResources.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <mutex>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
constexpr std::size_t word_size = sizeof(std::uint32_t);

std::size_t padded_word_bytes(std::size_t byte_count) noexcept
{
    return std::max<std::size_t>(((byte_count + word_size - 1) / word_size) * word_size, word_size);
}

id<MTLBuffer> create_shared_buffer(id<MTLDevice> device,
                                   const void* bytes,
                                   std::size_t byte_count)
{
    const std::size_t allocation_size = padded_word_bytes(byte_count);
    id<MTLBuffer> buffer = [device newBufferWithLength:allocation_size
                                               options:MTLResourceStorageModeShared];
    if (!buffer)
        return nil;

    std::memset(buffer.contents, 0, allocation_size);
    if (bytes && byte_count)
        std::memcpy(buffer.contents, bytes, byte_count);
    return buffer;
}

id<MTLTexture> create_r32uint_buffer_texture(id<MTLBuffer> buffer,
                                             std::size_t source_byte_count)
{
    if (!buffer)
        return nil;

    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor new];
    descriptor.textureType = MTLTextureTypeTextureBuffer;
    descriptor.pixelFormat = MTLPixelFormatR32Uint;
    descriptor.width = padded_word_bytes(source_byte_count) / word_size;
    descriptor.height = 1;
    descriptor.depth = 1;
    descriptor.mipmapLevelCount = 1;
    descriptor.arrayLength = 1;
    descriptor.sampleCount = 1;
    descriptor.storageMode = MTLStorageModeShared;
    descriptor.cpuCacheMode = MTLCPUCacheModeDefaultCache;
    descriptor.usage = MTLTextureUsageShaderRead;
    return [buffer newTextureWithDescriptor:descriptor offset:0 bytesPerRow:0];
}
} // namespace

struct vertex_resource_set::implementation
{
    mutable std::mutex mutex;
    __strong id<MTLBuffer> persistent_buffer = nil;
    __strong id<MTLBuffer> transient_buffer = nil;
    __strong id<MTLTexture> persistent_texture = nil;
    __strong id<MTLTexture> transient_texture = nil;
    __strong id<MTLBuffer> draw_parameters_buffer = nil;
    __strong id<MTLBuffer> vertex_context_buffer = nil;
    std::size_t uploaded_bytes = 0;
    bool is_ready = false;
};

vertex_resource_set::vertex_resource_set()
    : m_impl(std::make_unique<implementation>())
{
}

vertex_resource_set::~vertex_resource_set()
{
    clear();
}

bool vertex_resource_set::upload_and_bind(void* metal_device,
                                          void* render_command_encoder,
                                          const geometry_packet& packet,
                                          const vertex_resource_bindings& bindings,
                                          std::string& error)
{
    if (!validate_geometry_packet(packet, error))
        return false;
    if (!bindings.complete())
    {
        error = "Metal vertex resource upload requires complete reflected vertex bindings.";
        return false;
    }

    id<MTLDevice> device = metal_device ? (__bridge id<MTLDevice>)metal_device : nil;
    id<MTLRenderCommandEncoder> encoder = render_command_encoder
        ? (__bridge id<MTLRenderCommandEncoder>)render_command_encoder
        : nil;
    if (!device || !encoder)
    {
        error = "Metal vertex resource upload requires a live device and render encoder.";
        return false;
    }

    std::scoped_lock lock(m_impl->mutex);
    m_impl->is_ready = false;
    m_impl->uploaded_bytes = 0;

    @autoreleasepool
    {
        const void* persistent_bytes = packet.persistent_vertex_bytes.empty()
            ? nullptr
            : packet.persistent_vertex_bytes.data();
        const void* transient_bytes = packet.transient_vertex_bytes.empty()
            ? nullptr
            : packet.transient_vertex_bytes.data();

        id<MTLBuffer> persistent_buffer = create_shared_buffer(
            device, persistent_bytes, packet.persistent_vertex_bytes.size());
        id<MTLBuffer> transient_buffer = create_shared_buffer(
            device, transient_bytes, packet.transient_vertex_bytes.size());
        id<MTLBuffer> draw_parameters_buffer = create_shared_buffer(
            device, &packet.draw_parameters, sizeof(packet.draw_parameters));
        id<MTLBuffer> vertex_context_buffer = create_shared_buffer(
            device, &packet.vertex_context, sizeof(packet.vertex_context));
        if (!persistent_buffer || !transient_buffer ||
            !draw_parameters_buffer || !vertex_context_buffer)
        {
            error = "Metal could not allocate one or more RPCS3 vertex resources.";
            return false;
        }

        id<MTLTexture> persistent_texture = create_r32uint_buffer_texture(
            persistent_buffer, packet.persistent_vertex_bytes.size());
        id<MTLTexture> transient_texture = create_r32uint_buffer_texture(
            transient_buffer, packet.transient_vertex_bytes.size());
        if (!persistent_texture || !transient_texture)
        {
            error = "Metal could not create R32Uint texture views for RPCS3 vertex streams.";
            return false;
        }

        [encoder setVertexTexture:persistent_texture atIndex:bindings.persistent_vertex_texture];
        [encoder setVertexTexture:transient_texture atIndex:bindings.transient_vertex_texture];
        [encoder setVertexBuffer:draw_parameters_buffer
                          offset:0
                         atIndex:bindings.draw_parameters_buffer];
        [encoder setVertexBuffer:vertex_context_buffer
                          offset:0
                         atIndex:bindings.vertex_context_buffer];

        m_impl->persistent_buffer = persistent_buffer;
        m_impl->transient_buffer = transient_buffer;
        m_impl->persistent_texture = persistent_texture;
        m_impl->transient_texture = transient_texture;
        m_impl->draw_parameters_buffer = draw_parameters_buffer;
        m_impl->vertex_context_buffer = vertex_context_buffer;
        m_impl->uploaded_bytes = packet.total_vertex_bytes() +
            sizeof(packet.draw_parameters) + sizeof(packet.vertex_context);
        m_impl->is_ready = true;
        error.clear();
        return true;
    }
}

void vertex_resource_set::clear() noexcept
{
    if (!m_impl)
        return;

    std::scoped_lock lock(m_impl->mutex);
    m_impl->persistent_buffer = nil;
    m_impl->transient_buffer = nil;
    m_impl->persistent_texture = nil;
    m_impl->transient_texture = nil;
    m_impl->draw_parameters_buffer = nil;
    m_impl->vertex_context_buffer = nil;
    m_impl->uploaded_bytes = 0;
    m_impl->is_ready = false;
}

bool vertex_resource_set::ready() const noexcept
{
    if (!m_impl)
        return false;
    std::scoped_lock lock(m_impl->mutex);
    return m_impl->is_ready;
}

std::size_t vertex_resource_set::uploaded_byte_count() const noexcept
{
    if (!m_impl)
        return 0;
    std::scoped_lock lock(m_impl->mutex);
    return m_impl->uploaded_bytes;
}
} // namespace rpcs3::ios::render::metal_rsx
