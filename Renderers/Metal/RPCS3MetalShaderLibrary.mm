#include "RPCS3MetalShaderLibrary.h"

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

#include <mutex>
#include <string>
#include <unordered_map>
#include <utility>

namespace rpcs3::ios::render::metal_rsx
{
namespace
{
std::string make_cache_key(const translated_shader& shader)
{
    std::string key;
    key.reserve(shader.source.size() + shader.entry_point.size() + 3);
    key.push_back(shader.stage == shader_stage::vertex ? 'v' : 'f');
    key.push_back('\0');
    key.append(shader.entry_point);
    key.push_back('\0');
    key.append(shader.source);
    return key;
}

std::string metal_error_message(NSError* error, const char* fallback)
{
    if (!error)
        return fallback;
    const char* description = error.localizedDescription.UTF8String;
    return description && *description ? std::string(description) : std::string(fallback);
}
} // namespace

struct shader_library_cache::implementation
{
    struct cache_entry
    {
        __strong id<MTLLibrary> library = nil;
        __strong id<MTLFunction> function = nil;
    };

    mutable std::mutex mutex;
    __strong id<MTLDevice> device = nil;
    std::unordered_map<std::string, cache_entry> shaders;
};

shader_library_cache::shader_library_cache()
    : m_impl(std::make_unique<implementation>())
{
}

shader_library_cache::~shader_library_cache()
{
    clear();
}

bool shader_library_cache::initialize(void* metal_device, std::string& error)
{
    id<MTLDevice> device = metal_device ? (__bridge id<MTLDevice>)metal_device : nil;
    if (!device)
    {
        error = "Metal shader cache requires a valid MTLDevice.";
        return false;
    }

    std::scoped_lock lock(m_impl->mutex);
    m_impl->shaders.clear();
    m_impl->device = device;
    error.clear();
    return true;
}

bool shader_library_cache::get_or_compile(const translated_shader& shader,
                                          compiled_shader& output,
                                          std::string& error)
{
    output = {};
    if (shader.source.empty() || shader.entry_point.empty())
    {
        error = "Metal shader cache received empty MSL source or entry point.";
        return false;
    }

    const std::string key = make_cache_key(shader);
    std::scoped_lock lock(m_impl->mutex);
    if (!m_impl->device)
    {
        error = "Metal shader cache is not initialized.";
        return false;
    }

    if (const auto existing = m_impl->shaders.find(key); existing != m_impl->shaders.end())
    {
        output.library = (__bridge void*)existing->second.library;
        output.function = (__bridge void*)existing->second.function;
        error.clear();
        return true;
    }

    @autoreleasepool
    {
        NSString* source = [[NSString alloc] initWithBytes:shader.source.data()
                                                    length:shader.source.size()
                                                  encoding:NSUTF8StringEncoding];
        NSString* entry_point = [[NSString alloc] initWithBytes:shader.entry_point.data()
                                                         length:shader.entry_point.size()
                                                       encoding:NSUTF8StringEncoding];
        if (!source || !entry_point)
        {
            error = "Translated MSL source or entry point is not valid UTF-8.";
            return false;
        }

        MTLCompileOptions* options = [MTLCompileOptions new];

        NSError* compile_error = nil;
        id<MTLLibrary> library = [m_impl->device newLibraryWithSource:source
                                                              options:options
                                                                error:&compile_error];
        if (!library)
        {
            error = "Metal failed to compile translated RSX MSL: " +
                metal_error_message(compile_error, "unknown MSL compiler error");
            return false;
        }

        id<MTLFunction> function = [library newFunctionWithName:entry_point];
        if (!function)
        {
            error = "Compiled Metal library does not contain entry point '" + shader.entry_point + "'.";
            return false;
        }

        auto [inserted, created] = m_impl->shaders.emplace(
            key,
            implementation::cache_entry{library, function});
        if (!created)
        {
            inserted->second.library = library;
            inserted->second.function = function;
        }

        output.library = (__bridge void*)inserted->second.library;
        output.function = (__bridge void*)inserted->second.function;
        error.clear();
        return true;
    }
}

void shader_library_cache::clear() noexcept
{
    if (!m_impl)
        return;

    std::scoped_lock lock(m_impl->mutex);
    m_impl->shaders.clear();
    m_impl->device = nil;
}

bool shader_library_cache::initialized() const noexcept
{
    if (!m_impl)
        return false;
    std::scoped_lock lock(m_impl->mutex);
    return m_impl->device != nil;
}

std::size_t shader_library_cache::size() const noexcept
{
    if (!m_impl)
        return 0;
    std::scoped_lock lock(m_impl->mutex);
    return m_impl->shaders.size();
}
} // namespace rpcs3::ios::render::metal_rsx
