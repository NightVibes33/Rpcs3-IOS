#pragma once

#include "../RPCS3RendererBackend.h"

#include <memory>

namespace rpcs3::ios::render
{
class vulkan_renderer final : public renderer_backend
{
public:
    vulkan_renderer();
    ~vulkan_renderer() override;

    backend_kind kind() const noexcept override;
    bool initialize(const surface_config& config, std::string& error) override;
    bool resize(std::uint32_t pixel_width,
                std::uint32_t pixel_height,
                float content_scale,
                std::string& error) override;
    bool present_test_frame(float red,
                            float green,
                            float blue,
                            float alpha,
                            std::string& error) override;
    void shutdown() noexcept override;
    backend_status status() const override;

private:
    struct implementation;
    std::unique_ptr<implementation> m_impl;
};
} // namespace rpcs3::ios::render
