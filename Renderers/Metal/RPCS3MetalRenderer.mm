#include "RPCS3MetalRenderer.h"
#include "../Apple/RPCS3AppleSurface.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <utility>

namespace rpcs3::ios::render
{
struct metal_renderer::implementation
{
    apple_surface* surface = nullptr;
    __strong id<MTLDevice> device = nil;
    __strong id<MTLCommandQueue> queue = nil;
    __strong CAMetalLayer* layer = nil;
    __strong id<CAMetalDrawable> current_drawable = nil;
    __strong id<MTLCommandBuffer> current_command_buffer = nil;
    __strong id<MTLRenderCommandEncoder> current_encoder = nil;
    metal_rsx::shader_library_cache shader_cache;
    metal_rsx::render_pipeline_cache pipeline_cache;
    metal_rsx::vertex_resource_set vertex_resources;
    backend_status status;
    std::uint32_t width = 1;
    std::uint32_t height = 1;
    float scale = 1.0f;
    std::uint64_t submitted_draws = 0;
};

metal_renderer::metal_renderer()
    : m_impl(std::make_unique<implementation>())
{
    m_impl->status.kind = backend_kind::metal;
    m_impl->status.compiled = true;
    m_impl->status.message = "Native Metal backend is compiled but not initialized.";
}

metal_renderer::~metal_renderer()
{
    shutdown();
}

backend_kind metal_renderer::kind() const noexcept
{
    return backend_kind::metal;
}

bool metal_renderer::initialize(const surface_config& config, std::string& error)
{
    shutdown();
    m_impl->status.kind = backend_kind::metal;
    m_impl->status.compiled = true;

    @autoreleasepool
    {
        m_impl->device = MTLCreateSystemDefaultDevice();
        if (!m_impl->device)
        {
            error = "Metal is unavailable on this iOS device.";
            m_impl->status.message = error;
            return false;
        }

        m_impl->queue = [m_impl->device newCommandQueue];
        if (!m_impl->queue)
        {
            error = "Metal could not create a command queue.";
            m_impl->status.message = error;
            m_impl->device = nil;
            return false;
        }

        if (!m_impl->shader_cache.initialize((__bridge void*)m_impl->device, error))
        {
            m_impl->status.message = error;
            m_impl->queue = nil;
            m_impl->device = nil;
            return false;
        }

        if (!m_impl->pipeline_cache.initialize((__bridge void*)m_impl->device, error))
        {
            m_impl->status.message = error;
            m_impl->shader_cache.clear();
            m_impl->queue = nil;
            m_impl->device = nil;
            return false;
        }

        m_impl->width = std::max<std::uint32_t>(config.pixel_width, 1);
        m_impl->height = std::max<std::uint32_t>(config.pixel_height, 1);
        m_impl->scale = std::max(config.content_scale, 1.0f);
        m_impl->surface = create_apple_metal_surface(config.native_view,
                                                     m_impl->width,
                                                     m_impl->height,
                                                     m_impl->scale,
                                                     error);
        if (!m_impl->surface)
        {
            m_impl->status.message = error;
            m_impl->pipeline_cache.clear();
            m_impl->shader_cache.clear();
            m_impl->queue = nil;
            m_impl->device = nil;
            return false;
        }

        m_impl->layer = (__bridge CAMetalLayer*)apple_surface_layer(m_impl->surface);
        m_impl->layer.device = m_impl->device;
        m_impl->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        CGColorSpaceRef colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        m_impl->layer.colorspace = colorspace;
        if (colorspace)
            CGColorSpaceRelease(colorspace);
        m_impl->layer.framebufferOnly = YES;
        m_impl->layer.maximumDrawableCount = 3;
        (void)config.vsync;
        m_impl->layer.allowsNextDrawableTimeout = YES;

        m_impl->submitted_draws = 0;
        m_impl->status.initialized = true;
        m_impl->status.surface_ready = true;
        m_impl->status.device_name = m_impl->device.name.UTF8String ?: "Apple GPU";
        m_impl->status.message = "Native Metal device, shader/pipeline caches, command queue, and CAMetalLayer are ready.";
        error.clear();
        return true;
    }
}

bool metal_renderer::resize(std::uint32_t pixel_width,
                            std::uint32_t pixel_height,
                            float content_scale,
                            std::string& error)
{
    if (!m_impl->status.initialized || !m_impl->surface)
    {
        error = "Metal renderer is not initialized.";
        return false;
    }

    if (frame_active())
    {
        error = "Metal surface cannot be resized while a frame is being encoded.";
        return false;
    }

    m_impl->width = std::max<std::uint32_t>(pixel_width, 1);
    m_impl->height = std::max<std::uint32_t>(pixel_height, 1);
    m_impl->scale = std::max(content_scale, 1.0f);
    resize_apple_surface(m_impl->surface, m_impl->width, m_impl->height, m_impl->scale);
    error.clear();
    return true;
}

bool metal_renderer::compile_spirv_shader(
    std::span<const std::uint32_t> spirv,
    metal_rsx::shader_stage stage,
    metal_rsx::compiled_shader& output,
    std::string& error)
{
    output = {};
    if (!m_impl->status.initialized || !m_impl->shader_cache.initialized())
    {
        error = "Metal renderer must be initialized before compiling an RSX shader.";
        return false;
    }

    metal_rsx::translated_shader translated;
    if (!metal_rsx::translate_spirv_to_msl(spirv, stage, translated, error))
    {
        m_impl->status.message = error;
        return false;
    }

    if (!m_impl->shader_cache.get_or_compile(translated, output, error))
    {
        m_impl->status.message = error;
        return false;
    }

    m_impl->status.message = stage == metal_rsx::shader_stage::vertex
        ? "Translated and cached an RPCS3 vertex shader for native Metal."
        : "Translated and cached an RPCS3 fragment shader for native Metal.";
    error.clear();
    return true;
}

std::size_t metal_renderer::cached_shader_count() const noexcept
{
    return m_impl ? m_impl->shader_cache.size() : 0;
}

bool metal_renderer::get_or_create_render_pipeline(
    const metal_rsx::render_pipeline_request& request,
    metal_rsx::compiled_render_pipeline& output,
    std::string& error)
{
    output = {};
    if (!m_impl->status.initialized || !m_impl->pipeline_cache.initialized())
    {
        error = "Metal renderer must be initialized before creating an RSX render pipeline.";
        return false;
    }

    if (!m_impl->pipeline_cache.get_or_create(request, output, error))
    {
        m_impl->status.message = error;
        return false;
    }

    m_impl->status.message = "Created or reused a native Metal render pipeline for translated RSX shaders.";
    error.clear();
    return true;
}

std::size_t metal_renderer::cached_pipeline_count() const noexcept
{
    return m_impl ? m_impl->pipeline_cache.size() : 0;
}

bool metal_renderer::begin_frame(float red,
                                 float green,
                                 float blue,
                                 float alpha,
                                 std::string& error)
{
    if (!m_impl->status.initialized || !m_impl->queue || !m_impl->layer)
    {
        error = "Metal renderer is not initialized.";
        return false;
    }

    if (frame_active())
    {
        error = "Metal already has an active frame encoder.";
        return false;
    }

    @autoreleasepool
    {
        id<CAMetalDrawable> drawable = [m_impl->layer nextDrawable];
        if (!drawable)
        {
            error = "Metal did not provide a drawable.";
            m_impl->status.message = error;
            return false;
        }

        id<MTLCommandBuffer> command_buffer = [m_impl->queue commandBuffer];
        if (!command_buffer)
        {
            error = "Metal could not allocate a command buffer.";
            m_impl->status.message = error;
            return false;
        }

        MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = drawable.texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        pass.colorAttachments[0].clearColor = MTLClearColorMake(std::clamp(red, 0.0f, 1.0f),
                                                                std::clamp(green, 0.0f, 1.0f),
                                                                std::clamp(blue, 0.0f, 1.0f),
                                                                std::clamp(alpha, 0.0f, 1.0f));

        id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
        if (!encoder)
        {
            error = "Metal could not create a render command encoder.";
            m_impl->status.message = error;
            return false;
        }

        command_buffer.label = @"RPCS3 iOS Metal frame";
        encoder.label = @"RPCS3 translated RSX draws";
        [encoder setViewport:(MTLViewport){0.0, 0.0,
                                           static_cast<double>(m_impl->width),
                                           static_cast<double>(m_impl->height),
                                           0.0, 1.0}];

        m_impl->current_drawable = drawable;
        m_impl->current_command_buffer = command_buffer;
        m_impl->current_encoder = encoder;
        m_impl->status.message = "Native Metal frame encoder is active.";
        error.clear();
        return true;
    }
}

bool metal_renderer::bind_render_pipeline(
    const metal_rsx::compiled_render_pipeline& pipeline,
    std::string& error)
{
    if (!frame_active() || !m_impl->current_encoder)
    {
        error = "Metal render pipeline binding requires an active frame encoder.";
        return false;
    }
    if (!pipeline.state)
    {
        error = "Metal render pipeline binding received an empty pipeline state.";
        return false;
    }

    id<MTLRenderPipelineState> state = (__bridge id<MTLRenderPipelineState>)pipeline.state;
    [m_impl->current_encoder setRenderPipelineState:state];
    m_impl->status.message = "Bound the translated RPCS3 render pipeline to the active Metal frame.";
    error.clear();
    return true;
}

bool metal_renderer::upload_and_bind_vertex_resources(
    const metal_rsx::geometry_packet& packet,
    const metal_rsx::vertex_resource_bindings& bindings,
    std::string& error)
{
    if (!frame_active() || !m_impl->device || !m_impl->current_encoder)
    {
        error = "Metal vertex resource binding requires an active frame encoder.";
        return false;
    }

    if (!m_impl->vertex_resources.upload_and_bind(
            (__bridge void*)m_impl->device,
            (__bridge void*)m_impl->current_encoder,
            packet,
            bindings,
            error))
    {
        m_impl->status.message = error;
        return false;
    }

    m_impl->status.message = "Uploaded and bound RPCS3 vertex streams and exact shader environment records.";
    error.clear();
    return true;
}

std::size_t metal_renderer::uploaded_vertex_resource_bytes() const noexcept
{
    return m_impl ? m_impl->vertex_resources.uploaded_byte_count() : 0;
}

bool metal_renderer::submit_draw(const metal_rsx::draw_submission& submission,
                                 std::string& error)
{
    if (!frame_active())
    {
        error = "Metal draw submission requires an active frame encoder.";
        return false;
    }

    if (!metal_rsx::validate_draw_submission(submission, error))
        return false;

    @autoreleasepool
    {
        id<MTLRenderPipelineState> pipeline =
            (__bridge id<MTLRenderPipelineState>)submission.render_pipeline_state;
        id<MTLDepthStencilState> depth_stencil = submission.depth_stencil_state
            ? (__bridge id<MTLDepthStencilState>)submission.depth_stencil_state
            : nil;

        id<MTLBuffer> vertex_buffer = [m_impl->device
            newBufferWithBytes:submission.vertex_buffer.bytes
                         length:submission.vertex_buffer.byte_count
                        options:MTLResourceStorageModeShared];
        if (!vertex_buffer)
        {
            error = "Metal could not upload the translated vertex buffer.";
            m_impl->status.message = error;
            return false;
        }

        [m_impl->current_encoder setRenderPipelineState:pipeline];
        if (depth_stencil)
            [m_impl->current_encoder setDepthStencilState:depth_stencil];
        [m_impl->current_encoder setStencilFrontReferenceValue:submission.stencil_reference_front
                                            backReferenceValue:submission.stencil_reference_back];
        [m_impl->current_encoder setVertexBuffer:vertex_buffer offset:0 atIndex:0];

        const MTLPrimitiveType primitive = static_cast<MTLPrimitiveType>(submission.primitive_type);
        if (submission.indexed())
        {
            id<MTLBuffer> index_buffer = [m_impl->device
                newBufferWithBytes:submission.index_buffer.bytes
                             length:submission.index_buffer.byte_count
                            options:MTLResourceStorageModeShared];
            if (!index_buffer)
            {
                error = "Metal could not upload the translated index buffer.";
                m_impl->status.message = error;
                return false;
            }

            const MTLIndexType index_type = submission.indices == metal_rsx::index_format::uint16
                ? MTLIndexTypeUInt16
                : MTLIndexTypeUInt32;
            [m_impl->current_encoder drawIndexedPrimitives:primitive
                                                indexCount:submission.index_count
                                                 indexType:index_type
                                               indexBuffer:index_buffer
                                         indexBufferOffset:0
                                             instanceCount:submission.instance_count];
        }
        else
        {
            [m_impl->current_encoder drawPrimitives:primitive
                                       vertexStart:submission.vertex_start
                                       vertexCount:submission.vertex_count
                                     instanceCount:submission.instance_count];
        }

        ++m_impl->submitted_draws;
        error.clear();
        return true;
    }
}

bool metal_renderer::end_frame(std::string& error)
{
    if (!frame_active() || !m_impl->current_command_buffer || !m_impl->current_drawable)
    {
        error = "Metal has no active frame to present.";
        return false;
    }

    @autoreleasepool
    {
        [m_impl->current_encoder endEncoding];
        [m_impl->current_command_buffer presentDrawable:m_impl->current_drawable];
        [m_impl->current_command_buffer commit];

        m_impl->current_encoder = nil;
        m_impl->current_command_buffer = nil;
        m_impl->current_drawable = nil;
        m_impl->status.frame_presented = true;
        m_impl->status.message = m_impl->submitted_draws == 0
            ? "Native Metal submitted and presented an empty frame."
            : "Native Metal submitted translated RSX draw commands and presented the frame.";
        error.clear();
        return true;
    }
}

bool metal_renderer::frame_active() const noexcept
{
    return m_impl && m_impl->current_encoder != nil;
}

bool metal_renderer::present_test_frame(float red,
                                        float green,
                                        float blue,
                                        float alpha,
                                        std::string& error)
{
    if (!begin_frame(red, green, blue, alpha, error))
        return false;
    return end_frame(error);
}

void metal_renderer::shutdown() noexcept
{
    if (!m_impl)
        return;

    @autoreleasepool
    {
        if (m_impl->current_encoder)
            [m_impl->current_encoder endEncoding];
        m_impl->current_encoder = nil;
        m_impl->current_command_buffer = nil;
        m_impl->current_drawable = nil;

        m_impl->vertex_resources.clear();
        m_impl->pipeline_cache.clear();
        m_impl->shader_cache.clear();
        m_impl->layer.device = nil;
        m_impl->layer = nil;
        m_impl->queue = nil;
        m_impl->device = nil;
        destroy_apple_surface(std::exchange(m_impl->surface, nullptr));
    }

    m_impl->submitted_draws = 0;
    m_impl->status.initialized = false;
    m_impl->status.surface_ready = false;
    m_impl->status.frame_presented = false;
    m_impl->status.message = "Native Metal backend is stopped.";
}

backend_status metal_renderer::status() const
{
    return m_impl->status;
}
} // namespace rpcs3::ios::render
