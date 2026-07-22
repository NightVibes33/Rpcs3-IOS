#pragma once

#include "../RPCS3RendererBackend.h"
#include "RPCS3MetalDrawSubmission.h"
#include "RPCS3MetalRenderPipelineCache.h"
#include "RPCS3MetalShaderLibrary.h"

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

    bool compile_spirv_shader(std::span<const std::uint32_t> spirv,
                              metal_rsx::shader_stage stage,
                              metal_rsx::compiled_shader& output,
                              std::string& error);
    [[nodiscard]] std::size_t cached_shader_count() const noexcept;

    bool get_or_create_render_pipeline(
        const metal_rsx::render_pipeline_request& request,
        metal_rsx::compiled_render_pipeline& output,
        std::string& error);
    [[nodiscard]] std::size_t cached_pipeline_count() const noexcept;

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
