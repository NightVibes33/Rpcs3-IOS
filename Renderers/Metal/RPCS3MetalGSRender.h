#pragma once

#include "Emu/RSX/GSRender.h"
#include "RPCS3MetalPipelineState.h"
#include "RPCS3MetalRenderer.h"
#include "RPCS3MetalRSXFormats.h"
#include "RPCS3MetalRSXShaderFrontend.h"

namespace rpcs3::ios::render
{
class metal_gs_render final : public GSRender
{
public:
    explicit metal_gs_render(utils::serial* archive) noexcept;
    metal_gs_render() noexcept : metal_gs_render(nullptr) {}

    u64 get_cycles() final;
    void on_init_thread() override;
    void on_exit() override;
    void flip(const rsx::display_flip_info_t& info) override;

private:
    void end() override;
    bool initialize_backend();
    void capture_rsx_draw_state();
    bool prepare_current_shader_pipeline(std::string& error);

    metal_renderer m_backend;
    metal_rsx::rsx_shader_frontend m_shader_frontend;
    bool m_backend_initialized = false;
    bool m_shader_frontend_initialized = false;
    u64 m_presented_frames = 0;
    u64 m_translated_draws = 0;
    u64 m_topology_rewrite_draws = 0;
    u64 m_compiled_program_pairs = 0;
    metal_rsx::primitive_mapping m_primitive_mapping{};
    metal_rsx::depth_stencil_state m_depth_stencil_state{};
    metal_rsx::color_blend_state m_color_blend_state{};
    metal_rsx::frontend_shader m_vertex_frontend_shader{};
    metal_rsx::frontend_shader m_fragment_frontend_shader{};
    metal_rsx::compiled_shader m_vertex_shader{};
    metal_rsx::compiled_shader m_fragment_shader{};
    metal_rsx::compiled_render_pipeline m_render_pipeline{};
};
} // namespace rpcs3::ios::render
