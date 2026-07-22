#include "IOSPlatform.h"

#import <Metal/Metal.h>
#include <sys/mman.h>

namespace rpcs3::ios
{
platform_capabilities query_platform_capabilities() noexcept
{
    bool jit = false;
#ifdef MAP_JIT
    const auto page_size = static_cast<size_t>(getpagesize());
    void* memory = mmap(nullptr, page_size, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (memory != MAP_FAILED)
    {
        jit = true;
        munmap(memory, page_size);
    }
#endif

    return {
        .physical_device = true,
        .dynamic_code_supported = jit,
        .metal_available = MTLCreateSystemDefaultDevice() != nil,
        .vulkan_surface_available = false,
    };
}
}
