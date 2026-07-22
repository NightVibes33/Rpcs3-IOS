#pragma once

#include "../RPCS3RendererBackend.h"
#include "RPCS3MetalDrawSubmission.h"

#include <memory>

namespace rpcs3::ios::render
{
class metal_renderer final : public renderer_backend
{
public:
    metal_renderer();
    ~metal_renderer() override;

    backend_kind kind() const noexcept override;
    bool initialize(const surface_config& config, std::string& error) override;
    bool resize(std::uint32_t pixel_width,
                std::uint32_t pixel_height,
                float content_scale,
                std::string& error) override;

    bool begin_frame(float red,
                     float green,
                     float blue,
                     float alpha,
                     std::string& error);
    bool submit_draw(const metal_rsx::draw_submission& submission,
                     std::string& error);
    bool end_frame(std::string& error);
    [[nodiscard]] bool frame_active() const noexcept;

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
