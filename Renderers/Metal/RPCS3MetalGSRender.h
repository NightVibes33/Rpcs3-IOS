#pragma once

#include "Emu/RSX/GSRender.h"
#include "RPCS3MetalRenderer.h"

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

    metal_renderer m_backend;
    bool m_backend_initialized = false;
    u64 m_presented_frames = 0;
};
} // namespace rpcs3::ios::render
