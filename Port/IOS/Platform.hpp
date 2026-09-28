#pragma once

#include <TargetConditionals.h>

#if !defined(__APPLE__) || !TARGET_OS_IOS || TARGET_OS_SIMULATOR
#error RPCS3 iOS platform overlay requires a physical iOS target.
#endif

#define RPCS3_IOS 1
#define RPCS3_MOBILE 1
#define RPCS3_HAS_DESKTOP_UI 0
#define RPCS3_HAS_PROCESS_SPAWN 0
#define RPCS3_HAS_DLOPEN 0
#define RPCS3_HAS_POSIX_FILES 1
#define RPCS3_HAS_MACH_THREADS 1
#define RPCS3_HAS_APPLE_JIT_API 1

namespace rpcs3::ios
{
inline constexpr bool is_device = true;
inline constexpr bool has_desktop_ui = false;
inline constexpr bool has_process_spawn = false;
inline constexpr bool has_dynamic_loader = false;
inline constexpr bool has_interpreter = true;
inline constexpr bool has_jit = false;
inline constexpr bool has_renderer = false;
}
