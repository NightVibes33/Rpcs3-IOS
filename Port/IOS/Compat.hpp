#pragma once

#include "Platform.hpp"

#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <sys/mman.h>
#include <unistd.h>

namespace rpcs3::ios
{
inline std::size_t page_size() noexcept
{
    const long value = ::sysconf(_SC_PAGESIZE);
    return value > 0 ? static_cast<std::size_t>(value) : 16u * 1024u;
}

inline void* reserve_memory(std::size_t size) noexcept
{
    void* result = ::mmap(nullptr, size, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    return result == MAP_FAILED ? nullptr : result;
}

inline bool release_memory(void* address, std::size_t size) noexcept
{
    return address && ::munmap(address, size) == 0;
}

inline bool protect_memory(void* address, std::size_t size, int protection) noexcept
{
    return address && ::mprotect(address, size, protection) == 0;
}

inline void* allocate_jit_memory(std::size_t size) noexcept
{
#if defined(MAP_JIT)
    void* result = ::mmap(nullptr, size, PROT_READ | PROT_WRITE,
        MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    return result == MAP_FAILED ? nullptr : result;
#else
    (void)size;
    errno = ENOTSUP;
    return nullptr;
#endif
}
}
