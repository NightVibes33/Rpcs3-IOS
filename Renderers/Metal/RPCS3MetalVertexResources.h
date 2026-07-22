#pragma once

#include "RPCS3MetalGeometryPacket.h"
#include "RPCS3MetalResourceBindings.h"

#include <cstddef>
#include <memory>
#include <string>

namespace rpcs3::ios::render::metal_rsx
{
/*
 * Owns the Metal resources for one converted RPCS3 draw and binds them to the
 * post-SPIRV-Cross vertex slots. The encoder/device are opaque so the interface
 * remains usable from C++ renderer code while the implementation stays ObjC++.
 */
class vertex_resource_set final
{
public:
    vertex_resource_set();
    ~vertex_resource_set();

    vertex_resource_set(const vertex_resource_set&) = delete;
    vertex_resource_set& operator=(const vertex_resource_set&) = delete;

    bool upload_and_bind(void* metal_device,
                         void* render_command_encoder,
                         const geometry_packet& packet,
                         const vertex_resource_bindings& bindings,
                         std::string& error);
    void clear() noexcept;

    [[nodiscard]] bool ready() const noexcept;
    [[nodiscard]] std::size_t uploaded_byte_count() const noexcept;

private:
    struct implementation;
    std::unique_ptr<implementation> m_impl;
};
} // namespace rpcs3::ios::render::metal_rsx
