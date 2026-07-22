#include "RPCS3MetalRenderPipelineCache.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <string>
#include <unordered_map>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
std::string make_pipeline_key(const render_pipeline_request& request)
{
    const auto pointer_value = [](const void* value)
    {
        return static_cast<unsigned long long>(reinterpret_cast<std::uintptr_t>(value));
    };

    const color_blend_state& blend = request.color_blend;
    return std::to_string(pointer_value(request.vertex_function)) + ":" +
        std::to_string(pointer_value(request.fragment_function)) + ":" +
        std::to_string(request.color_pixel_format) + ":" +
        std::to_string(request.depth_pixel_format) + ":" +
        std::to_string(request.stencil_pixel_format) + ":" +
        std::to_string(request.sample_count) + ":" +
        std::to_string(blend.blend_enabled) + ":" +
        std::to_string(blend.source_rgb_factor) + ":" +
        std::to_string(blend.destination_rgb_factor) + ":" +
        std::to_string(blend.rgb_equation) + ":" +
        std::to_string(blend.source_alpha_factor) + ":" +
        std::to_string(blend.destination_alpha_factor) + ":" +
        std::to_string(blend.alpha_equation) + ":" +
        std::to_string(blend.color_write_mask);
}

std::string metal_error_message(NSError* error)
{
    if (!error)
        return "unknown Metal pipeline compiler error";
    const char* description = error.localizedDescription.UTF8String;
    return description && *description
        ? std::string(description)
        : std::string("unknown Metal pipeline compiler error");
}
} // namespace

struct render_pipeline_cache::implementation
{
    mutable std::mutex mutex;
    __strong id<MTLDevice> device = nil;
    std::unordered_map<std::string, __strong id<MTLRenderPipelineState>> pipelines;
};

render_pipeline_cache::render_pipeline_cache()
    : m_impl(std::make_unique<implementation>())
{
}

render_pipeline_cache::~render_pipeline_cache()
{
    clear();
}

bool render_pipeline_cache::initialize(void* metal_device, std::string& error)
{
    id<MTLDevice> device = metal_device ? (__bridge id<MTLDevice>)metal_device : nil;
    if (!device)
    {
        error = "Metal render pipeline cache requires a valid MTLDevice.";
        return false;
    }

    std::scoped_lock lock(m_impl->mutex);
    m_impl->pipelines.clear();
    m_impl->device = device;
    error.clear();
    return true;
}

bool render_pipeline_cache::get_or_create(const render_pipeline_request& request,
                                          compiled_render_pipeline& output,
                                          std::string& error)
{
    output = {};
    if (!request.vertex_function)
    {
        error = "Metal render pipeline requires a compiled vertex function.";
        return false;
    }
    if (request.color_pixel_format == static_cast<std::uint32_t>(MTLPixelFormatInvalid) &&
        request.depth_pixel_format == static_cast<std::uint32_t>(MTLPixelFormatInvalid) &&
        request.stencil_pixel_format == static_cast<std::uint32_t>(MTLPixelFormatInvalid))
    {
        error = "Metal render pipeline requires at least one color, depth, or stencil attachment.";
        return false;
    }

    const std::string key = make_pipeline_key(request);
    std::scoped_lock lock(m_impl->mutex);
    if (!m_impl->device)
    {
        error = "Metal render pipeline cache is not initialized.";
        return false;
    }

    if (const auto existing = m_impl->pipelines.find(key); existing != m_impl->pipelines.end())
    {
        output.state = (__bridge void*)existing->second;
        error.clear();
        return true;
    }

    @autoreleasepool
    {
        id<MTLFunction> vertex = (__bridge id<MTLFunction>)request.vertex_function;
        id<MTLFunction> fragment = request.fragment_function
            ? (__bridge id<MTLFunction>)request.fragment_function
            : nil;

        MTLRenderPipelineDescriptor* descriptor = [MTLRenderPipelineDescriptor new];
        descriptor.label = @"RPCS3 translated RSX pipeline";
        descriptor.vertexFunction = vertex;
        descriptor.fragmentFunction = fragment;
        descriptor.sampleCount = std::max<std::uint32_t>(request.sample_count, 1);
        descriptor.colorAttachments[0].pixelFormat =
            static_cast<MTLPixelFormat>(request.color_pixel_format);
        descriptor.depthAttachmentPixelFormat =
            static_cast<MTLPixelFormat>(request.depth_pixel_format);
        descriptor.stencilAttachmentPixelFormat =
            static_cast<MTLPixelFormat>(request.stencil_pixel_format);
        configure_color_attachment(descriptor.colorAttachments[0], request.color_blend);

        NSError* pipeline_error = nil;
        id<MTLRenderPipelineState> state =
            [m_impl->device newRenderPipelineStateWithDescriptor:descriptor error:&pipeline_error];
        if (!state)
        {
            error = "Metal failed to create the translated RSX render pipeline: " +
                metal_error_message(pipeline_error);
            return false;
        }

        auto [inserted, created] = m_impl->pipelines.emplace(key, state);
        if (!created)
            inserted->second = state;
        output.state = (__bridge void*)inserted->second;
        error.clear();
        return true;
    }
}

void render_pipeline_cache::clear() noexcept
{
    if (!m_impl)
        return;
    std::scoped_lock lock(m_impl->mutex);
    m_impl->pipelines.clear();
    m_impl->device = nil;
}

bool render_pipeline_cache::initialized() const noexcept
{
    if (!m_impl)
        return false;
    std::scoped_lock lock(m_impl->mutex);
    return m_impl->device != nil;
}

std::size_t render_pipeline_cache::size() const noexcept
{
    if (!m_impl)
        return 0;
    std::scoped_lock lock(m_impl->mutex);
    return m_impl->pipelines.size();
}
} // namespace rpcs3::ios::render::metal_rsx
