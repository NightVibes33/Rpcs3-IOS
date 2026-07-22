#include "RPCS3VulkanRenderer.h"
#include "../Apple/RPCS3AppleSurface.h"

#define VK_USE_PLATFORM_METAL_EXT 1
#include <vulkan/vulkan.h>

#import <QuartzCore/CAMetalLayer.h>

#include <algorithm>
#include <array>
#include <cstring>
#include <limits>
#include <utility>
#include <vector>

#ifndef VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME
#define VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME "VK_KHR_portability_enumeration"
#endif
#ifndef VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR
#define VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR 0x00000001
#endif
#ifndef VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME
#define VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME "VK_KHR_portability_subset"
#endif

namespace rpcs3::ios::render
{
namespace
{
const char* result_name(VkResult result)
{
    switch (result)
    {
    case VK_SUCCESS: return "VK_SUCCESS";
    case VK_NOT_READY: return "VK_NOT_READY";
    case VK_TIMEOUT: return "VK_TIMEOUT";
    case VK_EVENT_SET: return "VK_EVENT_SET";
    case VK_EVENT_RESET: return "VK_EVENT_RESET";
    case VK_INCOMPLETE: return "VK_INCOMPLETE";
    case VK_ERROR_OUT_OF_HOST_MEMORY: return "VK_ERROR_OUT_OF_HOST_MEMORY";
    case VK_ERROR_OUT_OF_DEVICE_MEMORY: return "VK_ERROR_OUT_OF_DEVICE_MEMORY";
    case VK_ERROR_INITIALIZATION_FAILED: return "VK_ERROR_INITIALIZATION_FAILED";
    case VK_ERROR_DEVICE_LOST: return "VK_ERROR_DEVICE_LOST";
    case VK_ERROR_MEMORY_MAP_FAILED: return "VK_ERROR_MEMORY_MAP_FAILED";
    case VK_ERROR_LAYER_NOT_PRESENT: return "VK_ERROR_LAYER_NOT_PRESENT";
    case VK_ERROR_EXTENSION_NOT_PRESENT: return "VK_ERROR_EXTENSION_NOT_PRESENT";
    case VK_ERROR_FEATURE_NOT_PRESENT: return "VK_ERROR_FEATURE_NOT_PRESENT";
    case VK_ERROR_INCOMPATIBLE_DRIVER: return "VK_ERROR_INCOMPATIBLE_DRIVER";
    case VK_ERROR_TOO_MANY_OBJECTS: return "VK_ERROR_TOO_MANY_OBJECTS";
    case VK_ERROR_FORMAT_NOT_SUPPORTED: return "VK_ERROR_FORMAT_NOT_SUPPORTED";
    case VK_ERROR_SURFACE_LOST_KHR: return "VK_ERROR_SURFACE_LOST_KHR";
    case VK_ERROR_NATIVE_WINDOW_IN_USE_KHR: return "VK_ERROR_NATIVE_WINDOW_IN_USE_KHR";
    case VK_SUBOPTIMAL_KHR: return "VK_SUBOPTIMAL_KHR";
    case VK_ERROR_OUT_OF_DATE_KHR: return "VK_ERROR_OUT_OF_DATE_KHR";
    default: return "VK_ERROR_UNKNOWN";
    }
}

bool has_extension(const std::vector<VkExtensionProperties>& extensions, const char* name)
{
    return std::any_of(extensions.begin(), extensions.end(), [name](const VkExtensionProperties& property)
    {
        return std::strcmp(property.extensionName, name) == 0;
    });
}

VkCompositeAlphaFlagBitsKHR choose_composite_alpha(VkCompositeAlphaFlagsKHR supported)
{
    constexpr std::array choices = {
        VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    };
    for (const auto choice : choices)
        if (supported & choice) return choice;
    return VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
}
} // namespace

struct vulkan_renderer::implementation
{
    apple_surface* apple = nullptr;
    __strong CAMetalLayer* metal_layer = nil;
    surface_config config;
    backend_status status;

    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physical_device = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue graphics_queue = VK_NULL_HANDLE;
    std::uint32_t graphics_queue_family = std::numeric_limits<std::uint32_t>::max();
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkFormat swapchain_format = VK_FORMAT_UNDEFINED;
    VkExtent2D swapchain_extent{1, 1};
    VkRenderPass render_pass = VK_NULL_HANDLE;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkSemaphore image_available = VK_NULL_HANDLE;
    VkSemaphore render_finished = VK_NULL_HANDLE;
    VkFence frame_fence = VK_NULL_HANDLE;
    std::vector<VkImage> images;
    std::vector<VkImageView> image_views;
    std::vector<VkFramebuffer> framebuffers;
    std::vector<VkCommandBuffer> command_buffers;

    void destroy_swapchain() noexcept
    {
        if (!device)
            return;
        if (!command_buffers.empty() && command_pool)
            vkFreeCommandBuffers(device, command_pool, static_cast<std::uint32_t>(command_buffers.size()), command_buffers.data());
        command_buffers.clear();
        for (VkFramebuffer framebuffer : framebuffers)
            vkDestroyFramebuffer(device, framebuffer, nullptr);
        framebuffers.clear();
        if (render_pass)
            vkDestroyRenderPass(device, render_pass, nullptr);
        render_pass = VK_NULL_HANDLE;
        for (VkImageView view : image_views)
            vkDestroyImageView(device, view, nullptr);
        image_views.clear();
        images.clear();
        if (swapchain)
            vkDestroySwapchainKHR(device, swapchain, nullptr);
        swapchain = VK_NULL_HANDLE;
    }

    bool create_swapchain(std::string& error)
    {
        if (!device || !surface)
        {
            error = "Vulkan device or surface is unavailable.";
            return false;
        }

        vkDeviceWaitIdle(device);
        destroy_swapchain();

        VkSurfaceCapabilitiesKHR capabilities{};
        VkResult result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &capabilities);
        if (result != VK_SUCCESS)
        {
            error = std::string("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed: ") + result_name(result);
            return false;
        }

        std::uint32_t format_count = 0;
        result = vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, nullptr);
        if (result != VK_SUCCESS || format_count == 0)
        {
            error = std::string("MoltenVK exposed no surface formats: ") + result_name(result);
            return false;
        }
        std::vector<VkSurfaceFormatKHR> formats(format_count);
        result = vkGetPhysicalDeviceSurfaceFormatsKHR(physical_device, surface, &format_count, formats.data());
        if (result != VK_SUCCESS)
        {
            error = std::string("vkGetPhysicalDeviceSurfaceFormatsKHR failed: ") + result_name(result);
            return false;
        }

        VkSurfaceFormatKHR chosen = formats.front();
        for (const VkSurfaceFormatKHR& candidate : formats)
        {
            if ((candidate.format == VK_FORMAT_B8G8R8A8_UNORM || candidate.format == VK_FORMAT_B8G8R8A8_SRGB) &&
                candidate.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            {
                chosen = candidate;
                break;
            }
        }
        swapchain_format = chosen.format;

        if (capabilities.currentExtent.width != std::numeric_limits<std::uint32_t>::max())
        {
            swapchain_extent = capabilities.currentExtent;
        }
        else
        {
            swapchain_extent.width = std::clamp(std::max(config.pixel_width, 1u),
                                                capabilities.minImageExtent.width,
                                                capabilities.maxImageExtent.width);
            swapchain_extent.height = std::clamp(std::max(config.pixel_height, 1u),
                                                 capabilities.minImageExtent.height,
                                                 capabilities.maxImageExtent.height);
        }

        std::uint32_t image_count = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount > 0)
            image_count = std::min(image_count, capabilities.maxImageCount);

        VkSwapchainCreateInfoKHR swapchain_info{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
        swapchain_info.surface = surface;
        swapchain_info.minImageCount = image_count;
        swapchain_info.imageFormat = chosen.format;
        swapchain_info.imageColorSpace = chosen.colorSpace;
        swapchain_info.imageExtent = swapchain_extent;
        swapchain_info.imageArrayLayers = 1;
        swapchain_info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        swapchain_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
        swapchain_info.preTransform = capabilities.currentTransform;
        swapchain_info.compositeAlpha = choose_composite_alpha(capabilities.supportedCompositeAlpha);
        swapchain_info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
        swapchain_info.clipped = VK_TRUE;

        result = vkCreateSwapchainKHR(device, &swapchain_info, nullptr, &swapchain);
        if (result != VK_SUCCESS)
        {
            error = std::string("vkCreateSwapchainKHR failed: ") + result_name(result);
            return false;
        }

        result = vkGetSwapchainImagesKHR(device, swapchain, &image_count, nullptr);
        if (result != VK_SUCCESS || image_count == 0)
        {
            error = std::string("vkGetSwapchainImagesKHR failed: ") + result_name(result);
            destroy_swapchain();
            return false;
        }
        images.resize(image_count);
        result = vkGetSwapchainImagesKHR(device, swapchain, &image_count, images.data());
        if (result != VK_SUCCESS)
        {
            error = std::string("vkGetSwapchainImagesKHR failed: ") + result_name(result);
            destroy_swapchain();
            return false;
        }

        image_views.reserve(images.size());
        for (VkImage image : images)
        {
            VkImageViewCreateInfo view_info{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
            view_info.image = image;
            view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
            view_info.format = swapchain_format;
            view_info.components = {VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY,
                                    VK_COMPONENT_SWIZZLE_IDENTITY, VK_COMPONENT_SWIZZLE_IDENTITY};
            view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            view_info.subresourceRange.levelCount = 1;
            view_info.subresourceRange.layerCount = 1;
            VkImageView view = VK_NULL_HANDLE;
            result = vkCreateImageView(device, &view_info, nullptr, &view);
            if (result != VK_SUCCESS)
            {
                error = std::string("vkCreateImageView failed: ") + result_name(result);
                destroy_swapchain();
                return false;
            }
            image_views.push_back(view);
        }

        VkAttachmentDescription color_attachment{};
        color_attachment.format = swapchain_format;
        color_attachment.samples = VK_SAMPLE_COUNT_1_BIT;
        color_attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        color_attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        color_attachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        color_attachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        color_attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        color_attachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

        VkAttachmentReference color_reference{};
        color_reference.attachment = 0;
        color_reference.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

        VkSubpassDescription subpass{};
        subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
        subpass.colorAttachmentCount = 1;
        subpass.pColorAttachments = &color_reference;

        VkSubpassDependency dependency{};
        dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
        dependency.dstSubpass = 0;
        dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
        dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

        VkRenderPassCreateInfo render_pass_info{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
        render_pass_info.attachmentCount = 1;
        render_pass_info.pAttachments = &color_attachment;
        render_pass_info.subpassCount = 1;
        render_pass_info.pSubpasses = &subpass;
        render_pass_info.dependencyCount = 1;
        render_pass_info.pDependencies = &dependency;
        result = vkCreateRenderPass(device, &render_pass_info, nullptr, &render_pass);
        if (result != VK_SUCCESS)
        {
            error = std::string("vkCreateRenderPass failed: ") + result_name(result);
            destroy_swapchain();
            return false;
        }

        framebuffers.reserve(image_views.size());
        for (VkImageView view : image_views)
        {
            VkFramebufferCreateInfo framebuffer_info{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
            framebuffer_info.renderPass = render_pass;
            framebuffer_info.attachmentCount = 1;
            framebuffer_info.pAttachments = &view;
            framebuffer_info.width = swapchain_extent.width;
            framebuffer_info.height = swapchain_extent.height;
            framebuffer_info.layers = 1;
            VkFramebuffer framebuffer = VK_NULL_HANDLE;
            result = vkCreateFramebuffer(device, &framebuffer_info, nullptr, &framebuffer);
            if (result != VK_SUCCESS)
            {
                error = std::string("vkCreateFramebuffer failed: ") + result_name(result);
                destroy_swapchain();
                return false;
            }
            framebuffers.push_back(framebuffer);
        }

        command_buffers.resize(images.size());
        VkCommandBufferAllocateInfo command_info{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        command_info.commandPool = command_pool;
        command_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        command_info.commandBufferCount = static_cast<std::uint32_t>(command_buffers.size());
        result = vkAllocateCommandBuffers(device, &command_info, command_buffers.data());
        if (result != VK_SUCCESS)
        {
            error = std::string("vkAllocateCommandBuffers failed: ") + result_name(result);
            destroy_swapchain();
            return false;
        }

        status.surface_ready = true;
        return true;
    }
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
    m_impl->config = config;
    m_impl->config.pixel_width = std::max(config.pixel_width, 1u);
    m_impl->config.pixel_height = std::max(config.pixel_height, 1u);
    m_impl->config.content_scale = std::max(config.content_scale, 1.0f);

    m_impl->apple = create_apple_metal_surface(config.native_view,
                                                m_impl->config.pixel_width,
                                                m_impl->config.pixel_height,
                                                m_impl->config.content_scale,
                                                error);
    if (!m_impl->apple)
    {
        m_impl->status.message = error;
        return false;
    }
    m_impl->metal_layer = (__bridge CAMetalLayer*)apple_surface_layer(m_impl->apple);

    VkApplicationInfo application_info{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    application_info.pApplicationName = "RPCS3 iOS";
    application_info.applicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);
    application_info.pEngineName = "RPCS3";
    application_info.engineVersion = VK_MAKE_API_VERSION(0, 0, 0, 40);
    application_info.apiVersion = VK_API_VERSION_1_2;

    const std::array instance_extensions = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
        VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME,
    };
    VkInstanceCreateInfo instance_info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    instance_info.flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    instance_info.pApplicationInfo = &application_info;
    instance_info.enabledExtensionCount = static_cast<std::uint32_t>(instance_extensions.size());
    instance_info.ppEnabledExtensionNames = instance_extensions.data();

    VkResult result = vkCreateInstance(&instance_info, nullptr, &m_impl->instance);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkCreateInstance failed: ") + result_name(result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    auto create_metal_surface = reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(
        vkGetInstanceProcAddr(m_impl->instance, "vkCreateMetalSurfaceEXT"));
    if (!create_metal_surface)
    {
        error = "MoltenVK did not expose vkCreateMetalSurfaceEXT.";
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    VkMetalSurfaceCreateInfoEXT surface_info{VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT};
    surface_info.pLayer = m_impl->metal_layer;
    result = create_metal_surface(m_impl->instance, &surface_info, nullptr, &m_impl->surface);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkCreateMetalSurfaceEXT failed: ") + result_name(result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    std::uint32_t device_count = 0;
    result = vkEnumeratePhysicalDevices(m_impl->instance, &device_count, nullptr);
    if (result != VK_SUCCESS || device_count == 0)
    {
        error = std::string("MoltenVK exposed no Vulkan physical device: ") + result_name(result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }
    std::vector<VkPhysicalDevice> devices(device_count);
    vkEnumeratePhysicalDevices(m_impl->instance, &device_count, devices.data());

    for (VkPhysicalDevice candidate : devices)
    {
        std::uint32_t queue_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queue_count, nullptr);
        std::vector<VkQueueFamilyProperties> queues(queue_count);
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queue_count, queues.data());
        for (std::uint32_t index = 0; index < queue_count; ++index)
        {
            VkBool32 present_supported = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(candidate, index, m_impl->surface, &present_supported);
            if ((queues[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) && present_supported)
            {
                m_impl->physical_device = candidate;
                m_impl->graphics_queue_family = index;
                break;
            }
        }
        if (m_impl->physical_device)
            break;
    }

    if (!m_impl->physical_device)
    {
        error = "MoltenVK exposed no graphics queue capable of presenting to the iOS CAMetalLayer.";
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    std::uint32_t extension_count = 0;
    vkEnumerateDeviceExtensionProperties(m_impl->physical_device, nullptr, &extension_count, nullptr);
    std::vector<VkExtensionProperties> extensions(extension_count);
    vkEnumerateDeviceExtensionProperties(m_impl->physical_device, nullptr, &extension_count, extensions.data());
    if (!has_extension(extensions, VK_KHR_SWAPCHAIN_EXTENSION_NAME))
    {
        error = "MoltenVK device does not expose VK_KHR_swapchain.";
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    std::vector<const char*> device_extensions = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    if (has_extension(extensions, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME))
        device_extensions.push_back(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);

    const float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    queue_info.queueFamilyIndex = m_impl->graphics_queue_family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;

    VkPhysicalDeviceFeatures features{};
    VkDeviceCreateInfo device_info{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = static_cast<std::uint32_t>(device_extensions.size());
    device_info.ppEnabledExtensionNames = device_extensions.data();
    device_info.pEnabledFeatures = &features;
    result = vkCreateDevice(m_impl->physical_device, &device_info, nullptr, &m_impl->device);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkCreateDevice failed: ") + result_name(result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }
    vkGetDeviceQueue(m_impl->device, m_impl->graphics_queue_family, 0, &m_impl->graphics_queue);

    VkCommandPoolCreateInfo command_pool_info{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    command_pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    command_pool_info.queueFamilyIndex = m_impl->graphics_queue_family;
    result = vkCreateCommandPool(m_impl->device, &command_pool_info, nullptr, &m_impl->command_pool);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkCreateCommandPool failed: ") + result_name(result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    VkSemaphoreCreateInfo semaphore_info{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    VkFenceCreateInfo fence_info{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    fence_info.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    if (vkCreateSemaphore(m_impl->device, &semaphore_info, nullptr, &m_impl->image_available) != VK_SUCCESS ||
        vkCreateSemaphore(m_impl->device, &semaphore_info, nullptr, &m_impl->render_finished) != VK_SUCCESS ||
        vkCreateFence(m_impl->device, &fence_info, nullptr, &m_impl->frame_fence) != VK_SUCCESS)
    {
        error = "Vulkan could not create frame synchronization objects.";
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    if (!m_impl->create_swapchain(error))
    {
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    VkPhysicalDeviceProperties properties{};
    vkGetPhysicalDeviceProperties(m_impl->physical_device, &properties);
    m_impl->status.initialized = true;
    m_impl->status.surface_ready = true;
    m_impl->status.device_name = properties.deviceName;
    m_impl->status.message = "MoltenVK created a Vulkan instance, Apple GPU device, Metal surface, and swapchain.";
    error.clear();
    return true;
}

bool vulkan_renderer::resize(std::uint32_t pixel_width,
                             std::uint32_t pixel_height,
                             float content_scale,
                             std::string& error)
{
    if (!m_impl->status.initialized || !m_impl->apple)
    {
        error = "Vulkan renderer is not initialized.";
        return false;
    }
    m_impl->config.pixel_width = std::max(pixel_width, 1u);
    m_impl->config.pixel_height = std::max(pixel_height, 1u);
    m_impl->config.content_scale = std::max(content_scale, 1.0f);
    resize_apple_surface(m_impl->apple,
                         m_impl->config.pixel_width,
                         m_impl->config.pixel_height,
                         m_impl->config.content_scale);
    return m_impl->create_swapchain(error);
}

bool vulkan_renderer::present_test_frame(float red,
                                         float green,
                                         float blue,
                                         float alpha,
                                         std::string& error)
{
    if (!m_impl->status.initialized || !m_impl->device || !m_impl->swapchain)
    {
        error = "Vulkan renderer is not initialized.";
        return false;
    }

    VkResult result = vkWaitForFences(m_impl->device, 1, &m_impl->frame_fence, VK_TRUE, UINT64_MAX);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkWaitForFences failed: ") + result_name(result);
        return false;
    }

    std::uint32_t image_index = 0;
    result = vkAcquireNextImageKHR(m_impl->device,
                                   m_impl->swapchain,
                                   UINT64_MAX,
                                   m_impl->image_available,
                                   VK_NULL_HANDLE,
                                   &image_index);
    if (result == VK_ERROR_OUT_OF_DATE_KHR)
        return m_impl->create_swapchain(error);
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR)
    {
        error = std::string("vkAcquireNextImageKHR failed: ") + result_name(result);
        return false;
    }

    vkResetFences(m_impl->device, 1, &m_impl->frame_fence);
    VkCommandBuffer command_buffer = m_impl->command_buffers.at(image_index);
    vkResetCommandBuffer(command_buffer, 0);

    VkCommandBufferBeginInfo begin_info{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin_info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    result = vkBeginCommandBuffer(command_buffer, &begin_info);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkBeginCommandBuffer failed: ") + result_name(result);
        return false;
    }

    VkClearValue clear{};
    clear.color.float32[0] = std::clamp(red, 0.0f, 1.0f);
    clear.color.float32[1] = std::clamp(green, 0.0f, 1.0f);
    clear.color.float32[2] = std::clamp(blue, 0.0f, 1.0f);
    clear.color.float32[3] = std::clamp(alpha, 0.0f, 1.0f);

    VkRenderPassBeginInfo pass_info{VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO};
    pass_info.renderPass = m_impl->render_pass;
    pass_info.framebuffer = m_impl->framebuffers.at(image_index);
    pass_info.renderArea.extent = m_impl->swapchain_extent;
    pass_info.clearValueCount = 1;
    pass_info.pClearValues = &clear;
    vkCmdBeginRenderPass(command_buffer, &pass_info, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdEndRenderPass(command_buffer);
    result = vkEndCommandBuffer(command_buffer);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkEndCommandBuffer failed: ") + result_name(result);
        return false;
    }

    const VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit_info{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit_info.waitSemaphoreCount = 1;
    submit_info.pWaitSemaphores = &m_impl->image_available;
    submit_info.pWaitDstStageMask = &wait_stage;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command_buffer;
    submit_info.signalSemaphoreCount = 1;
    submit_info.pSignalSemaphores = &m_impl->render_finished;
    result = vkQueueSubmit(m_impl->graphics_queue, 1, &submit_info, m_impl->frame_fence);
    if (result != VK_SUCCESS)
    {
        error = std::string("vkQueueSubmit failed: ") + result_name(result);
        return false;
    }

    VkPresentInfoKHR present_info{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present_info.waitSemaphoreCount = 1;
    present_info.pWaitSemaphores = &m_impl->render_finished;
    present_info.swapchainCount = 1;
    present_info.pSwapchains = &m_impl->swapchain;
    present_info.pImageIndices = &image_index;
    result = vkQueuePresentKHR(m_impl->graphics_queue, &present_info);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR)
    {
        if (!m_impl->create_swapchain(error))
            return false;
    }
    else if (result != VK_SUCCESS)
    {
        error = std::string("vkQueuePresentKHR failed: ") + result_name(result);
        return false;
    }

    m_impl->status.frame_presented = true;
    m_impl->status.message = "MoltenVK submitted and presented a Vulkan frame through Metal.";
    error.clear();
    return true;
}

void vulkan_renderer::shutdown() noexcept
{
    if (!m_impl)
        return;
    if (m_impl->device)
        vkDeviceWaitIdle(m_impl->device);
    m_impl->destroy_swapchain();
    if (m_impl->frame_fence)
        vkDestroyFence(m_impl->device, m_impl->frame_fence, nullptr);
    if (m_impl->render_finished)
        vkDestroySemaphore(m_impl->device, m_impl->render_finished, nullptr);
    if (m_impl->image_available)
        vkDestroySemaphore(m_impl->device, m_impl->image_available, nullptr);
    if (m_impl->command_pool)
        vkDestroyCommandPool(m_impl->device, m_impl->command_pool, nullptr);
    if (m_impl->device)
        vkDestroyDevice(m_impl->device, nullptr);
    if (m_impl->surface && m_impl->instance)
        vkDestroySurfaceKHR(m_impl->instance, m_impl->surface, nullptr);
    if (m_impl->instance)
        vkDestroyInstance(m_impl->instance, nullptr);

    m_impl->frame_fence = VK_NULL_HANDLE;
    m_impl->render_finished = VK_NULL_HANDLE;
    m_impl->image_available = VK_NULL_HANDLE;
    m_impl->command_pool = VK_NULL_HANDLE;
    m_impl->device = VK_NULL_HANDLE;
    m_impl->physical_device = VK_NULL_HANDLE;
    m_impl->graphics_queue = VK_NULL_HANDLE;
    m_impl->graphics_queue_family = std::numeric_limits<std::uint32_t>::max();
    m_impl->surface = VK_NULL_HANDLE;
    m_impl->instance = VK_NULL_HANDLE;
    m_impl->metal_layer = nil;
    destroy_apple_surface(std::exchange(m_impl->apple, nullptr));

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
