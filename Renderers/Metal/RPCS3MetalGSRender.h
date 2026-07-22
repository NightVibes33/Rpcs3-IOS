#pragma once

#include "Emu/RSX/GSRender.h"
#include "RPCS3MetalGeometryPacket.h"
#include "RPCS3MetalPipelineState.h"
#include "RPCS3MetalProgramCompiler.h"
#include "RPCS3MetalRenderer.h"
#include "RPCS3MetalResourceBindings.h"
#include "RPCS3MetalRSXFormats.h"

#include <string>

namespace rpcs3::ios::render
{
class metal_gs_render : public GSRender
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
    bool prepare_live_geometry_packet();
    bool bind_live_frame_resources();

    metal_renderer m_backend;
    bool m_backend_initialized = false;
    bool m_frame_has_live_resources = false;
    u64 m_presented_frames = 0;
    u64 m_translated_draws = 0;
    u64 m_topology_rewrite_draws = 0;
    u64 m_program_ready_draws = 0;
    u64 m_program_compile_failures = 0;
    u64 m_program_cache_hits = 0;
    u64 m_program_cache_misses = 0;
    u64 m_geometry_ready_draws = 0;
    u64 m_geometry_failures = 0;
    u64 m_resource_bound_draws = 0;
    u64 m_resource_binding_failures = 0;
    usz m_cached_vertex_program_hash = umax;
    usz m_cached_fragment_program_hash = umax;
    bool m_cached_program_pair_valid = false;
    metal_rsx::compiled_shader m_cached_vertex_shader{};
    metal_rsx::compiled_shader m_cached_fragment_shader{};
    metal_rsx::vertex_resource_bindings m_vertex_bindings{};
    metal_rsx::primitive_mapping m_primitive_mapping{};
    metal_rsx::depth_stencil_state m_depth_stencil_state{};
    metal_rsx::color_blend_state m_color_blend_state{};
    metal_rsx::compiled_render_pipeline m_active_pipeline{};
    rsx::vertex_input_layout m_vertex_layout{};
    metal_rsx::geometry_packet m_geometry_packet{};
    std::string m_last_program_error;
    std::string m_last_geometry_error;
    std::string m_last_binding_error;
};
} // namespace rpcs3::ios::render
