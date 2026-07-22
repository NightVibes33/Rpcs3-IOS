#pragma once

#include "Emu/RSX/GSRender.h"
#include "RPCS3MetalPipelineState.h"
#include "RPCS3MetalRenderer.h"
#include "RPCS3MetalRSXFormats.h"

namespace rpcs3::ios::render
{
// RPCS3's named_thread<Context> derives from the renderer context, so this
// class must remain derivable even though its virtual overrides are final.
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

    metal_renderer m_backend;
    bool m_backend_initialized = false;
    u64 m_presented_frames = 0;
    u64 m_translated_draws = 0;
    u64 m_topology_rewrite_draws = 0;
    metal_rsx::primitive_mapping m_primitive_mapping{};
    metal_rsx::depth_stencil_state m_depth_stencil_state{};
    metal_rsx::color_blend_state m_color_blend_state{};
};
} // namespace rpcs3::ios::render
