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
    backend_status status;
    std::uint32_t width = 1;
    std::uint32_t height = 1;
    float scale = 1.0f;
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
            m_impl->queue = nil;
            m_impl->device = nil;
            return false;
        }

        m_impl->layer = (__bridge CAMetalLayer*)apple_surface_layer(m_impl->surface);
        m_impl->layer.device = m_impl->device;
        m_impl->layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        m_impl->layer.colorspace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        m_impl->layer.framebufferOnly = YES;
        m_impl->layer.maximumDrawableCount = 3;
        m_impl->layer.displaySyncEnabled = config.vsync;
        m_impl->layer.allowsNextDrawableTimeout = YES;

        m_impl->status.initialized = true;
        m_impl->status.surface_ready = true;
        m_impl->status.device_name = m_impl->device.name.UTF8String ?: "Apple GPU";
        m_impl->status.message = "Native Metal device, command queue, and CAMetalLayer are ready.";
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

    m_impl->width = std::max<std::uint32_t>(pixel_width, 1);
    m_impl->height = std::max<std::uint32_t>(pixel_height, 1);
    m_impl->scale = std::max(content_scale, 1.0f);
    resize_apple_surface(m_impl->surface, m_impl->width, m_impl->height, m_impl->scale);
    error.clear();
    return true;
}

bool metal_renderer::present_test_frame(float red,
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

    @autoreleasepool
    {
        id<CAMetalDrawable> drawable = [m_impl->layer nextDrawable];
        if (!drawable)
        {
            error = "Metal did not provide a drawable.";
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

        id<MTLCommandBuffer> command_buffer = [m_impl->queue commandBuffer];
        if (!command_buffer)
        {
            error = "Metal could not allocate a command buffer.";
            m_impl->status.message = error;
            return false;
        }

        id<MTLRenderCommandEncoder> encoder = [command_buffer renderCommandEncoderWithDescriptor:pass];
        if (!encoder)
        {
            error = "Metal could not create a render command encoder.";
            m_impl->status.message = error;
            return false;
        }

        [encoder endEncoding];
        [command_buffer presentDrawable:drawable];
        [command_buffer commit];

        m_impl->status.frame_presented = true;
        m_impl->status.message = "Native Metal submitted and presented a frame.";
        error.clear();
        return true;
    }
}

void metal_renderer::shutdown() noexcept
{
    if (!m_impl)
        return;

    @autoreleasepool
    {
        m_impl->layer.device = nil;
        m_impl->layer = nil;
        m_impl->queue = nil;
        m_impl->device = nil;
        destroy_apple_surface(std::exchange(m_impl->surface, nullptr));
    }

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
