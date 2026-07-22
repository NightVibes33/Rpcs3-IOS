#pragma once

#include "RPCS3MetalShaderTranslator.h"

#include <memory>
#include <string>
#include <vector>

namespace rpcs3::ios::render::metal_rsx
{
struct compiled_shader
{
    void* library = nullptr;
    void* function = nullptr;
    shader_stage stage = shader_stage::vertex;
    std::vector<shader_resource_binding> resources;
};

class shader_library_cache final
{
public:
    shader_library_cache();
    ~shader_library_cache();

    shader_library_cache(const shader_library_cache&) = delete;
    shader_library_cache& operator=(const shader_library_cache&) = delete;

    bool initialize(void* metal_device, std::string& error);
    bool get_or_compile(const translated_shader& shader,
                        compiled_shader& output,
                        std::string& error);
    void clear() noexcept;
    [[nodiscard]] bool initialized() const noexcept;
    [[nodiscard]] std::size_t size() const noexcept;

private:
    struct implementation;
    std::unique_ptr<implementation> m_impl;
};
} // namespace rpcs3::ios::render::metal_rsx
