#pragma once

#include "Emu/RSX/GSRender.h"
#include "RPCS3MetalGeometryStaging.h"
#include "RPCS3MetalPipelineState.h"
#include "RPCS3MetalProgramCompiler.h"
#include "RPCS3MetalRenderer.h"
#include "RPCS3MetalRSXFormats.h"

#include <string>

namespace rpcs3::ios::render
{
class metal_gs_render final : public GSRender
{
public:
    explicit metal_gs_render(utils::serial* archive) noexcept;
    metal_gs_render() noexcept : metal_gs_render(nullptr) {}

    u64 get_cycles() final;
    void on_init_thread() override;
    void flip(const rsx::display_flip_info_t& info) override;

private:
    void end() override;
    bool initialize_backend();
    void capture_rsx_draw_state();
    bool prepare_live_program_pipeline();
    bool stage_live_geometry();

    metal_renderer m_backend;
    bool m_backend_initialized = false;
    u64 m_presented_frames = 0;
    u64 m_translated_draws = 0;
    u64 m_topology_rewrite_draws = 0;
    u64 m_program_ready_draws = 0;
    u64 m_program_compile_failures = 0;
    u64 m_geometry_ready_draws = 0;
    u64 m_geometry_stage_failures = 0;
    rsx::vertex_input_layout m_vertex_layout{};
    metal_rsx::staged_geometry m_staged_geometry{};
    metal_rsx::primitive_mapping m_primitive_mapping{};
    metal_rsx::depth_stencil_state m_depth_stencil_state{};
    metal_rsx::color_blend_state m_color_blend_state{};
    metal_rsx::compiled_render_pipeline m_active_pipeline{};
    std::string m_last_program_error;
    std::string m_last_geometry_error;
};
} // namespace rpcs3::ios::render
