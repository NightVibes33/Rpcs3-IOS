#pragma once

#include <TargetConditionals.h>

#if !defined(__APPLE__) || !TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#error "RPCS3 iOS platform layer requires a physical iOS target"
#endif

#define RPCS3_IOS 1
#define RPCS3_PLATFORM_MOBILE 1
#define RPCS3_PLATFORM_APPLE 1
#define RPCS3_PLATFORM_DESKTOP 0
#define RPCS3_HAS_FORK 0
#define RPCS3_HAS_DLOPEN 0
#define RPCS3_HAS_DESKTOP_WINDOWING 0
#define RPCS3_HAS_PROCESS_SPAWN 0

namespace rpcs3::ios
{
struct platform_capabilities
{
    bool physical_device;
    bool dynamic_code_supported;
    bool metal_available;
    bool vulkan_surface_available;
};

platform_capabilities query_platform_capabilities() noexcept;
}
