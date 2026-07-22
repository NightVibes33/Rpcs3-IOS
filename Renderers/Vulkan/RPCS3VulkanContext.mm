#include "RPCS3VulkanContext.h"

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
std::string vk_failure(const char* operation, VkResult result)
{
    return std::string(operation) + " failed with VkResult " + std::to_string(static_cast<int>(result)) + ".";
}

bool has_extension(const std::vector<VkExtensionProperties>& extensions, const char* name)
{
    return std::any_of(extensions.begin(), extensions.end(), [name](const VkExtensionProperties& extension)
    {
        return std::strcmp(extension.extensionName, name) == 0;
    });
}

VkCompositeAlphaFlagBitsKHR composite_alpha(VkCompositeAlphaFlagsKHR supported)
{
    constexpr std::array<VkCompositeAlphaFlagBitsKHR, 4> choices = {
        VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        VK_COMPOSITE_ALPHA_PRE_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_POST_MULTIPLIED_BIT_KHR,
        VK_COMPOSITE_ALPHA_INHERIT_BIT_KHR,
    };
    for (const auto choice : choices)
        if ((supported & choice) != 0) return choice;
    return VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
}
} // namespace

struct vulkan_context::implementation
{
    VkInstance instance = VK_NULL_HANDLE;
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkDevice device = VK_NULL_HANDLE;
    VkQueue queue = VK_NULL_HANDLE;
    std::uint32_t queue_family = std::numeric_limits<std::uint32_t>::max();
    VkSurfaceKHR surface = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkFormat format = VK_FORMAT_UNDEFINED;
    VkExtent2D extent{1, 1};
    VkRenderPass render_pass = VK_NULL_HANDLE;
    VkCommandPool command_pool = VK_NULL_HANDLE;
    VkSemaphore acquired = VK_NULL_HANDLE;
    VkSemaphore rendered = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    std::vector<VkImage> images;
    std::vector<VkImageView> views;
    std::vector<VkFramebuffer> framebuffers;
    std::vector<VkCommandBuffer> commands;
    std::uint32_t requested_width = 1;
    std::uint32_t requested_height = 1;
    bool vsync = true;
    vulkan_context_status status;

    void destroy_swapchain() noexcept
    {
        if (!device)
            return;
        if (!commands.empty() && command_pool)
            vkFreeCommandBuffers(device, command_pool, static_cast<std::uint32_t>(commands.size()), commands.data());
        commands.clear();
        for (VkFramebuffer value : framebuffers)
            vkDestroyFramebuffer(device, value, nullptr);
        framebuffers.clear();
        if (render_pass)
            vkDestroyRenderPass(device, render_pass, nullptr);
        render_pass = VK_NULL_HANDLE;
        for (VkImageView value : views)
            vkDestroyImageView(device, value, nullptr);
        views.clear();
        images.clear();
        if (swapchain)
            vkDestroySwapchainKHR(device, swapchain, nullptr);
        swapchain = VK_NULL_HANDLE;
        status.surface_ready = false;
    }

    bool create_swapchain(std::string& error)
    {
        if (!device || !physical || !surface)
        {
            error = "The Vulkan device or Metal surface is unavailable.";
            return false;
        }

        vkDeviceWaitIdle(device);
        destroy_swapchain();

        VkSurfaceCapabilitiesKHR capabilities{};
        VkResult result = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical, surface, &capabilities);
        if (result != VK_SUCCESS)
        {
            error = vk_failure("vkGetPhysicalDeviceSurfaceCapabilitiesKHR", result);
            return false;
        }

        std::uint32_t format_count = 0;
        result = vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &format_count, nullptr);
        if (result != VK_SUCCESS || format_count == 0)
        {
            error = result == VK_SUCCESS ? "MoltenVK exposed no surface formats."
                                         : vk_failure("vkGetPhysicalDeviceSurfaceFormatsKHR", result);
            return false;
        }
        std::vector<VkSurfaceFormatKHR> formats(format_count);
        result = vkGetPhysicalDeviceSurfaceFormatsKHR(physical, surface, &format_count, formats.data());
        if (result != VK_SUCCESS)
        {
            error = vk_failure("vkGetPhysicalDeviceSurfaceFormatsKHR", result);
            return false;
        }

        VkSurfaceFormatKHR chosen = formats.front();
        for (const auto& candidate : formats)
        {
            if ((candidate.format == VK_FORMAT_B8G8R8A8_UNORM || candidate.format == VK_FORMAT_B8G8R8A8_SRGB) &&
                candidate.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR)
            {
                chosen = candidate;
                break;
            }
        }
        format = chosen.format;

        if (capabilities.currentExtent.width != std::numeric_limits<std::uint32_t>::max())
        {
            extent = capabilities.currentExtent;
        }
        else
        {
            extent.width = std::clamp(requested_width,
                                      capabilities.minImageExtent.width,
                                      capabilities.maxImageExtent.width);
            extent.height = std::clamp(requested_height,
                                       capabilities.minImageExtent.height,
                                       capabilities.maxImageExtent.height);
        }

        std::uint32_t image_count = capabilities.minImageCount + 1;
        if (capabilities.maxImageCount != 0)
            image_count = std::min(image_count, capabilities.maxImageCount);

        VkSwapchainCreateInfoKHR swapchain_info{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
        swapchain_info.surface = surface;
        swapchain_info.minImageCount = image_count;
        swapchain_info.imageFormat = chosen.format;
        swapchain_info.imageColorSpace = chosen.colorSpace;
        swapchain_info.imageExtent = extent;
        swapchain_info.imageArrayLayers = 1;
        swapchain_info.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
        swapchain_info.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
        swapchain_info.preTransform = capabilities.currentTransform;
        swapchain_info.compositeAlpha = composite_alpha(capabilities.supportedCompositeAlpha);
        swapchain_info.presentMode = VK_PRESENT_MODE_FIFO_KHR;
        swapchain_info.clipped = VK_TRUE;

        result = vkCreateSwapchainKHR(device, &swapchain_info, nullptr, &swapchain);
        if (result != VK_SUCCESS)
        {
            error = vk_failure("vkCreateSwapchainKHR", result);
            return false;
        }

        result = vkGetSwapchainImagesKHR(device, swapchain, &image_count, nullptr);
        if (result != VK_SUCCESS || image_count == 0)
        {
            error = result == VK_SUCCESS ? "MoltenVK exposed no swapchain images."
                                         : vk_failure("vkGetSwapchainImagesKHR", result);
            destroy_swapchain();
            return false;
        }
        images.resize(image_count);
        result = vkGetSwapchainImagesKHR(device, swapchain, &image_count, images.data());
        if (result != VK_SUCCESS)
        {
            error = vk_failure("vkGetSwapchainImagesKHR", result);
            destroy_swapchain();
            return false;
        }

        for (VkImage image : images)
        {
            VkImageViewCreateInfo view_info{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
            view_info.image = image;
            view_info.viewType = VK_IMAGE_VIEW_TYPE_2D;
            view_info.format = format;
            view_info.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            view_info.subresourceRange.levelCount = 1;
            view_info.subresourceRange.layerCount = 1;
            VkImageView view = VK_NULL_HANDLE;
            result = vkCreateImageView(device, &view_info, nullptr, &view);
            if (result != VK_SUCCESS)
            {
                error = vk_failure("vkCreateImageView", result);
                destroy_swapchain();
                return false;
            }
            views.push_back(view);
        }

        VkAttachmentDescription attachment{};
        attachment.format = format;
        attachment.samples = VK_SAMPLE_COUNT_1_BIT;
        attachment.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
        attachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        attachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
        attachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
        attachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        attachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

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

        VkRenderPassCreateInfo pass_info{VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
        pass_info.attachmentCount = 1;
        pass_info.pAttachments = &attachment;
        pass_info.subpassCount = 1;
        pass_info.pSubpasses = &subpass;
        pass_info.dependencyCount = 1;
        pass_info.pDependencies = &dependency;
        result = vkCreateRenderPass(device, &pass_info, nullptr, &render_pass);
        if (result != VK_SUCCESS)
        {
            error = vk_failure("vkCreateRenderPass", result);
            destroy_swapchain();
            return false;
        }

        for (VkImageView view : views)
        {
            VkFramebufferCreateInfo framebuffer_info{VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
            framebuffer_info.renderPass = render_pass;
            framebuffer_info.attachmentCount = 1;
            framebuffer_info.pAttachments = &view;
            framebuffer_info.width = extent.width;
            framebuffer_info.height = extent.height;
            framebuffer_info.layers = 1;
            VkFramebuffer framebuffer = VK_NULL_HANDLE;
            result = vkCreateFramebuffer(device, &framebuffer_info, nullptr, &framebuffer);
            if (result != VK_SUCCESS)
            {
                error = vk_failure("vkCreateFramebuffer", result);
                destroy_swapchain();
                return false;
            }
            framebuffers.push_back(framebuffer);
        }

        commands.resize(images.size());
        VkCommandBufferAllocateInfo allocate_info{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        allocate_info.commandPool = command_pool;
        allocate_info.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        allocate_info.commandBufferCount = static_cast<std::uint32_t>(commands.size());
        result = vkAllocateCommandBuffers(device, &allocate_info, commands.data());
        if (result != VK_SUCCESS)
        {
            error = vk_failure("vkAllocateCommandBuffers", result);
            destroy_swapchain();
            return false;
        }

        status.surface_ready = true;
        error.clear();
        return true;
    }
};

vulkan_context::vulkan_context()
    : m_impl(std::make_unique<implementation>())
{
    m_impl->status.message = "MoltenVK context is not initialized.";
}

vulkan_context::~vulkan_context()
{
    shutdown();
}

bool vulkan_context::initialize(void* metal_layer,
                                std::uint32_t pixel_width,
                                std::uint32_t pixel_height,
                                bool vsync,
                                std::string& error)
{
    shutdown();
    m_impl->requested_width = std::max(pixel_width, 1u);
    m_impl->requested_height = std::max(pixel_height, 1u);
    m_impl->vsync = vsync;

    std::uint32_t instance_extension_count = 0;
    vkEnumerateInstanceExtensionProperties(nullptr, &instance_extension_count, nullptr);
    std::vector<VkExtensionProperties> instance_extensions(instance_extension_count);
    vkEnumerateInstanceExtensionProperties(nullptr, &instance_extension_count, instance_extensions.data());

    if (!has_extension(instance_extensions, VK_KHR_SURFACE_EXTENSION_NAME) ||
        !has_extension(instance_extensions, VK_EXT_METAL_SURFACE_EXTENSION_NAME))
    {
        error = "MoltenVK does not expose VK_KHR_surface and VK_EXT_metal_surface.";
        m_impl->status.message = error;
        return false;
    }

    std::vector<const char*> enabled_instance_extensions = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_EXT_METAL_SURFACE_EXTENSION_NAME,
    };
    VkInstanceCreateFlags instance_flags = 0;
    if (has_extension(instance_extensions, VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME))
    {
        enabled_instance_extensions.push_back(VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME);
        instance_flags |= VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR;
    }

    VkApplicationInfo app_info{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app_info.pApplicationName = "RPCS3 iOS";
    app_info.applicationVersion = VK_MAKE_API_VERSION(0, 0, 1, 0);
    app_info.pEngineName = "RPCS3";
    app_info.engineVersion = VK_MAKE_API_VERSION(0, 0, 0, 40);
    app_info.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instance_info{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    instance_info.flags = instance_flags;
    instance_info.pApplicationInfo = &app_info;
    instance_info.enabledExtensionCount = static_cast<std::uint32_t>(enabled_instance_extensions.size());
    instance_info.ppEnabledExtensionNames = enabled_instance_extensions.data();

    VkResult result = vkCreateInstance(&instance_info, nullptr, &m_impl->instance);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkCreateInstance", result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    const auto create_surface = reinterpret_cast<PFN_vkCreateMetalSurfaceEXT>(
        vkGetInstanceProcAddr(m_impl->instance, "vkCreateMetalSurfaceEXT"));
    if (!create_surface || !metal_layer)
    {
        error = "MoltenVK could not obtain a valid CAMetalLayer surface function or layer.";
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    VkMetalSurfaceCreateInfoEXT surface_info{VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT};
    surface_info.pLayer = (__bridge CAMetalLayer*)metal_layer;
    result = create_surface(m_impl->instance, &surface_info, nullptr, &m_impl->surface);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkCreateMetalSurfaceEXT", result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    std::uint32_t physical_count = 0;
    result = vkEnumeratePhysicalDevices(m_impl->instance, &physical_count, nullptr);
    if (result != VK_SUCCESS || physical_count == 0)
    {
        error = result == VK_SUCCESS ? "MoltenVK exposed no Apple GPU."
                                     : vk_failure("vkEnumeratePhysicalDevices", result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }
    std::vector<VkPhysicalDevice> physical_devices(physical_count);
    vkEnumeratePhysicalDevices(m_impl->instance, &physical_count, physical_devices.data());

    for (VkPhysicalDevice candidate : physical_devices)
    {
        std::uint32_t queue_count = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queue_count, nullptr);
        std::vector<VkQueueFamilyProperties> queues(queue_count);
        vkGetPhysicalDeviceQueueFamilyProperties(candidate, &queue_count, queues.data());
        for (std::uint32_t index = 0; index < queue_count; ++index)
        {
            VkBool32 can_present = VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(candidate, index, m_impl->surface, &can_present);
            if ((queues[index].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && can_present)
            {
                m_impl->physical = candidate;
                m_impl->queue_family = index;
                break;
            }
        }
        if (m_impl->physical)
            break;
    }

    if (!m_impl->physical)
    {
        error = "MoltenVK exposed no graphics queue that can present to the CAMetalLayer.";
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    std::uint32_t device_extension_count = 0;
    vkEnumerateDeviceExtensionProperties(m_impl->physical, nullptr, &device_extension_count, nullptr);
    std::vector<VkExtensionProperties> device_extensions(device_extension_count);
    vkEnumerateDeviceExtensionProperties(m_impl->physical, nullptr, &device_extension_count, device_extensions.data());
    if (!has_extension(device_extensions, VK_KHR_SWAPCHAIN_EXTENSION_NAME))
    {
        error = "MoltenVK does not expose VK_KHR_swapchain.";
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    std::vector<const char*> enabled_device_extensions = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    if (has_extension(device_extensions, VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME))
        enabled_device_extensions.push_back(VK_KHR_PORTABILITY_SUBSET_EXTENSION_NAME);

    const float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_info{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    queue_info.queueFamilyIndex = m_impl->queue_family;
    queue_info.queueCount = 1;
    queue_info.pQueuePriorities = &priority;

    VkDeviceCreateInfo device_info{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    device_info.queueCreateInfoCount = 1;
    device_info.pQueueCreateInfos = &queue_info;
    device_info.enabledExtensionCount = static_cast<std::uint32_t>(enabled_device_extensions.size());
    device_info.ppEnabledExtensionNames = enabled_device_extensions.data();

    result = vkCreateDevice(m_impl->physical, &device_info, nullptr, &m_impl->device);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkCreateDevice", result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }
    vkGetDeviceQueue(m_impl->device, m_impl->queue_family, 0, &m_impl->queue);

    VkCommandPoolCreateInfo pool_info{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pool_info.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pool_info.queueFamilyIndex = m_impl->queue_family;
    result = vkCreateCommandPool(m_impl->device, &pool_info, nullptr, &m_impl->command_pool);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkCreateCommandPool", result);
        m_impl->status.message = error;
        shutdown();
        return false;
    }

    VkSemaphoreCreateInfo semaphore_info{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
    VkFenceCreateInfo fence_info{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    fence_info.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    if (vkCreateSemaphore(m_impl->device, &semaphore_info, nullptr, &m_impl->acquired) != VK_SUCCESS ||
        vkCreateSemaphore(m_impl->device, &semaphore_info, nullptr, &m_impl->rendered) != VK_SUCCESS ||
        vkCreateFence(m_impl->device, &fence_info, nullptr, &m_impl->fence) != VK_SUCCESS)
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
    vkGetPhysicalDeviceProperties(m_impl->physical, &properties);
    m_impl->status.initialized = true;
    m_impl->status.device_name = properties.deviceName;
    m_impl->status.message = "MoltenVK created a Vulkan device, Metal surface, and swapchain.";
    error.clear();
    return true;
}

bool vulkan_context::resize(std::uint32_t pixel_width,
                            std::uint32_t pixel_height,
                            std::string& error)
{
    if (!m_impl->status.initialized)
    {
        error = "The MoltenVK context is not initialized.";
        return false;
    }
    m_impl->requested_width = std::max(pixel_width, 1u);
    m_impl->requested_height = std::max(pixel_height, 1u);
    return m_impl->create_swapchain(error);
}

bool vulkan_context::present_clear(float red,
                                   float green,
                                   float blue,
                                   float alpha,
                                   std::string& error)
{
    if (!m_impl->status.initialized || !m_impl->swapchain)
    {
        error = "The MoltenVK context is not initialized.";
        return false;
    }

    VkResult result = vkWaitForFences(m_impl->device, 1, &m_impl->fence, VK_TRUE, UINT64_MAX);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkWaitForFences", result);
        return false;
    }

    std::uint32_t image_index = 0;
    result = vkAcquireNextImageKHR(m_impl->device,
                                   m_impl->swapchain,
                                   UINT64_MAX,
                                   m_impl->acquired,
                                   VK_NULL_HANDLE,
                                   &image_index);
    if (result == VK_ERROR_OUT_OF_DATE_KHR)
        return m_impl->create_swapchain(error);
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR)
    {
        error = vk_failure("vkAcquireNextImageKHR", result);
        return false;
    }

    vkResetFences(m_impl->device, 1, &m_impl->fence);
    VkCommandBuffer command = m_impl->commands.at(image_index);
    vkResetCommandBuffer(command, 0);

    VkCommandBufferBeginInfo begin_info{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    begin_info.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    result = vkBeginCommandBuffer(command, &begin_info);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkBeginCommandBuffer", result);
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
    pass_info.renderArea.extent = m_impl->extent;
    pass_info.clearValueCount = 1;
    pass_info.pClearValues = &clear;
    vkCmdBeginRenderPass(command, &pass_info, VK_SUBPASS_CONTENTS_INLINE);
    vkCmdEndRenderPass(command);

    result = vkEndCommandBuffer(command);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkEndCommandBuffer", result);
        return false;
    }

    const VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSubmitInfo submit_info{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    submit_info.waitSemaphoreCount = 1;
    submit_info.pWaitSemaphores = &m_impl->acquired;
    submit_info.pWaitDstStageMask = &wait_stage;
    submit_info.commandBufferCount = 1;
    submit_info.pCommandBuffers = &command;
    submit_info.signalSemaphoreCount = 1;
    submit_info.pSignalSemaphores = &m_impl->rendered;
    result = vkQueueSubmit(m_impl->queue, 1, &submit_info, m_impl->fence);
    if (result != VK_SUCCESS)
    {
        error = vk_failure("vkQueueSubmit", result);
        return false;
    }

    VkPresentInfoKHR present_info{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    present_info.waitSemaphoreCount = 1;
    present_info.pWaitSemaphores = &m_impl->rendered;
    present_info.swapchainCount = 1;
    present_info.pSwapchains = &m_impl->swapchain;
    present_info.pImageIndices = &image_index;
    result = vkQueuePresentKHR(m_impl->queue, &present_info);
    if (result == VK_ERROR_OUT_OF_DATE_KHR || result == VK_SUBOPTIMAL_KHR)
    {
        if (!m_impl->create_swapchain(error))
            return false;
    }
    else if (result != VK_SUCCESS)
    {
        error = vk_failure("vkQueuePresentKHR", result);
        return false;
    }

    m_impl->status.frame_presented = true;
    m_impl->status.message = "MoltenVK submitted and presented a Vulkan frame through Metal.";
    error.clear();
    return true;
}

void vulkan_context::shutdown() noexcept
{
    if (!m_impl)
        return;
    if (m_impl->device)
        vkDeviceWaitIdle(m_impl->device);
    m_impl->destroy_swapchain();
    if (m_impl->fence && m_impl->device)
        vkDestroyFence(m_impl->device, m_impl->fence, nullptr);
    if (m_impl->rendered && m_impl->device)
        vkDestroySemaphore(m_impl->device, m_impl->rendered, nullptr);
    if (m_impl->acquired && m_impl->device)
        vkDestroySemaphore(m_impl->device, m_impl->acquired, nullptr);
    if (m_impl->command_pool && m_impl->device)
        vkDestroyCommandPool(m_impl->device, m_impl->command_pool, nullptr);
    if (m_impl->device)
        vkDestroyDevice(m_impl->device, nullptr);
    if (m_impl->surface && m_impl->instance)
        vkDestroySurfaceKHR(m_impl->instance, m_impl->surface, nullptr);
    if (m_impl->instance)
        vkDestroyInstance(m_impl->instance, nullptr);

    m_impl->instance = VK_NULL_HANDLE;
    m_impl->physical = VK_NULL_HANDLE;
    m_impl->device = VK_NULL_HANDLE;
    m_impl->queue = VK_NULL_HANDLE;
    m_impl->queue_family = std::numeric_limits<std::uint32_t>::max();
    m_impl->surface = VK_NULL_HANDLE;
    m_impl->command_pool = VK_NULL_HANDLE;
    m_impl->acquired = VK_NULL_HANDLE;
    m_impl->rendered = VK_NULL_HANDLE;
    m_impl->fence = VK_NULL_HANDLE;
    m_impl->status.initialized = false;
    m_impl->status.surface_ready = false;
    m_impl->status.frame_presented = false;
    m_impl->status.message = "MoltenVK context is stopped.";
}

vulkan_context_status vulkan_context::status() const
{
    return m_impl->status;
}
} // namespace rpcs3::ios::render
