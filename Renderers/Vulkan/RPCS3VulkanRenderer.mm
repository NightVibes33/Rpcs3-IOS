#include "RPCS3VulkanRenderer.h"
#include "RPCS3VulkanContext.h"
#include "../Apple/RPCS3AppleSurface.h"

#include <algorithm>
#include <utility>

namespace rpcs3::ios::render
{
struct vulkan_renderer::implementation
{
    apple_surface* surface = nullptr;
    vulkan_context context;
    backend_status status;
    std::uint32_t width = 1;
    std::uint32_t height = 1;
    float scale = 1.0f;
};

vulkan_renderer::vulkan_renderer()
    : m_impl(std::make_unique<implementation>())
{
    m_impl->status.kind = backend_kind::vulkan;
    m_impl->status.compiled = true;
    m_impl->status.message = "MoltenVK backend is compiled but not initialized.";
}

vulkan_renderer::~vulkan_renderer()
{
    shutdown();
}

backend_kind vulkan_renderer::kind() const noexcept
{
    return backend_kind::vulkan;
}

bool vulkan_renderer::initialize(const surface_config& config, std::string& error)
{
    shutdown();
    m_impl->status.kind = backend_kind::vulkan;
    m_impl->status.compiled = true;
    m_impl->width = std::max(config.pixel_width, 1u);
    m_impl->height = std::max(config.pixel_height, 1u);
    m_impl->scale = std::max(config.content_scale, 1.0f);

    m_impl->surface = create_apple_metal_surface(config.native_view,
                                                  m_impl->width,
                                                  m_impl->height,
                                                  m_impl->scale,
                                                  error);
    if (!m_impl->surface)
    {
        m_impl->status.message = error;
        return false;
    }

    if (!m_impl->context.initialize(apple_surface_layer(m_impl->surface),
                                    m_impl->width,
                                    m_impl->height,
                                    config.vsync,
                                    error))
    {
        m_impl->status.message = error;
        destroy_apple_surface(std::exchange(m_impl->surface, nullptr));
        return false;
    }

    const vulkan_context_status current = m_impl->context.status();
    m_impl->status.initialized = current.initialized;
    m_impl->status.surface_ready = current.surface_ready;
    m_impl->status.frame_presented = current.frame_presented;
    m_impl->status.device_name = current.device_name;
    m_impl->status.message = current.message;
    error.clear();
    return true;
}

bool vulkan_renderer::resize(std::uint32_t pixel_width,
                             std::uint32_t pixel_height,
                             float content_scale,
                             std::string& error)
{
    if (!m_impl->status.initialized || !m_impl->surface)
    {
        error = "Vulkan renderer is not initialized.";
        return false;
    }

    m_impl->width = std::max(pixel_width, 1u);
    m_impl->height = std::max(pixel_height, 1u);
    m_impl->scale = std::max(content_scale, 1.0f);
    resize_apple_surface(m_impl->surface, m_impl->width, m_impl->height, m_impl->scale);
    if (!m_impl->context.resize(m_impl->width, m_impl->height, error))
    {
        m_impl->status.message = error;
        return false;
    }
    return true;
}

bool vulkan_renderer::present_test_frame(float red,
                                         float green,
                                         float blue,
                                         float alpha,
                                         std::string& error)
{
    if (!m_impl->status.initialized)
    {
        error = "Vulkan renderer is not initialized.";
        return false;
    }
    if (!m_impl->context.present_clear(red, green, blue, alpha, error))
    {
        m_impl->status.message = error;
        return false;
    }

    const vulkan_context_status current = m_impl->context.status();
    m_impl->status.frame_presented = current.frame_presented;
    m_impl->status.message = current.message;
    return true;
}

void vulkan_renderer::shutdown() noexcept
{
    if (!m_impl)
        return;
    m_impl->context.shutdown();
    destroy_apple_surface(std::exchange(m_impl->surface, nullptr));
    m_impl->status.initialized = false;
    m_impl->status.surface_ready = false;
    m_impl->status.frame_presented = false;
    m_impl->status.message = "MoltenVK backend is stopped.";
}

backend_status vulkan_renderer::status() const
{
    return m_impl->status;
}
} // namespace rpcs3::ios::render
