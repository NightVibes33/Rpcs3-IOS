#include "RPCS3RendererBackend.h"
#include "Metal/RPCS3MetalRenderer.h"
#include "Vulkan/RPCS3VulkanRenderer.h"

namespace rpcs3::ios::render
{
std::unique_ptr<renderer_backend> create_renderer_backend(backend_kind kind)
{
    switch (kind)
    {
    case backend_kind::vulkan:
        return std::make_unique<vulkan_renderer>();
    case backend_kind::metal:
        return std::make_unique<metal_renderer>();
    }
    return {};
}

bool renderer_backend_compiled(backend_kind kind) noexcept
{
    switch (kind)
    {
    case backend_kind::vulkan:
#if defined(RPCS3_IOS_HAS_MOLTENVK)
        return true;
#else
        return false;
#endif
    case backend_kind::metal:
        return true;
    }
    return false;
}

const char* renderer_backend_name(backend_kind kind) noexcept
{
    switch (kind)
    {
    case backend_kind::vulkan: return "Vulkan (MoltenVK)";
    case backend_kind::metal: return "Metal";
    }
    return "Unknown";
}
} // namespace rpcs3::ios::render
