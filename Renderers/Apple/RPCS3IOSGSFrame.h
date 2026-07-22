#pragma once

#include "Emu/RSX/GSFrameBase.h"

#include <cstdint>
#include <mutex>
#include <string>

namespace rpcs3::ios::render
{
struct apple_surface;

class ios_gs_frame final : public GSFrameBase
{
public:
    ios_gs_frame();
    ~ios_gs_frame() override;

    void close() override;
    void reset() override;
    bool shown() override;
    void hide() override;
    void show() override;
    void toggle_fullscreen() override;

    void delete_context(draw_context_t context) override;
    draw_context_t make_context() override;
    void set_current(draw_context_t context) override;
    void flip(draw_context_t context, bool skip_frame = false) override;
    int client_width() override;
    int client_height() override;
    f64 client_display_rate() override;
    bool has_alpha() override;

    display_handle_t handle() const override;

    bool can_consume_frame() const override;
    void present_frame(std::vector<u8>&& data,
                       u32 pitch,
                       u32 width,
                       u32 height,
                       bool is_bgra) const override;
    void take_screenshot(std::vector<u8>&& data,
                         u32 width,
                         u32 height,
                         bool is_bgra) override;

    void update_title(double fps = 0.0);

private:
    bool ensure_surface() const;

    mutable std::mutex m_mutex;
    mutable apple_surface* m_surface = nullptr;
    mutable std::string m_last_error;
    std::uint32_t m_width = 1920;
    std::uint32_t m_height = 1080;
    bool m_visible = true;
};
} // namespace rpcs3::ios::render
