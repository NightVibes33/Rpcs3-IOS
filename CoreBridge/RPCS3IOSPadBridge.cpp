#include "RPCS3UpstreamRuntimeBridge.h"

#include "Emu/Io/pad_types.h"
#include "Input/pad_thread.h"

#include <cstdint>
#include <mutex>

namespace
{
constexpr std::uint32_t kUp       = 1u << 0;
constexpr std::uint32_t kDown     = 1u << 1;
constexpr std::uint32_t kLeft     = 1u << 2;
constexpr std::uint32_t kRight    = 1u << 3;
constexpr std::uint32_t kCross    = 1u << 4;
constexpr std::uint32_t kCircle   = 1u << 5;
constexpr std::uint32_t kSquare   = 1u << 6;
constexpr std::uint32_t kTriangle = 1u << 7;
constexpr std::uint32_t kL1       = 1u << 8;
constexpr std::uint32_t kR1       = 1u << 9;
constexpr std::uint32_t kL2       = 1u << 10;
constexpr std::uint32_t kR2       = 1u << 11;
constexpr std::uint32_t kL3       = 1u << 12;
constexpr std::uint32_t kR3       = 1u << 13;
constexpr std::uint32_t kStart    = 1u << 14;
constexpr std::uint32_t kSelect   = 1u << 15;
constexpr std::uint32_t kPS       = 1u << 16;

pad_thread* g_pad_owner = nullptr;
s32 g_ldd_handle = -1;

u16 pressure(std::uint32_t buttons, std::uint32_t mask)
{
    return (buttons & mask) ? 255 : 0;
}

u16 digital1(std::uint32_t buttons)
{
    u16 value = 0;
    if (buttons & kSelect) value |= CELL_PAD_CTRL_SELECT;
    if (buttons & kL3)     value |= CELL_PAD_CTRL_L3;
    if (buttons & kR3)     value |= CELL_PAD_CTRL_R3;
    if (buttons & kStart)  value |= CELL_PAD_CTRL_START;
    if (buttons & kUp)     value |= CELL_PAD_CTRL_UP;
    if (buttons & kRight)  value |= CELL_PAD_CTRL_RIGHT;
    if (buttons & kDown)   value |= CELL_PAD_CTRL_DOWN;
    if (buttons & kLeft)   value |= CELL_PAD_CTRL_LEFT;
    if (buttons & kPS)     value |= CELL_PAD_CTRL_PS;
    return value;
}

u16 digital2(std::uint32_t buttons)
{
    u16 value = 0;
    if (buttons & kL2)       value |= CELL_PAD_CTRL_L2;
    if (buttons & kR2)       value |= CELL_PAD_CTRL_R2;
    if (buttons & kL1)       value |= CELL_PAD_CTRL_L1;
    if (buttons & kR1)       value |= CELL_PAD_CTRL_R1;
    if (buttons & kTriangle) value |= CELL_PAD_CTRL_TRIANGLE;
    if (buttons & kCircle)   value |= CELL_PAD_CTRL_CIRCLE;
    if (buttons & kCross)    value |= CELL_PAD_CTRL_CROSS;
    if (buttons & kSquare)   value |= CELL_PAD_CTRL_SQUARE;
    return value;
}

std::shared_ptr<Pad> get_or_create_ios_pad()
{
    pad_thread* owner = pad::get_pad_thread(true);
    if (!owner || !pad::g_started)
        return {};

    if (owner != g_pad_owner)
    {
        g_pad_owner = owner;
        g_ldd_handle = -1;
    }

    if (g_ldd_handle < 0)
        g_ldd_handle = owner->AddLddPad();

    if (g_ldd_handle < 0 || static_cast<usz>(g_ldd_handle) >= owner->GetPads().size())
        return {};

    return owner->GetPads()[static_cast<usz>(g_ldd_handle)];
}
} // namespace

extern "C" int rpcs3_ios_upstream_set_pad_state(
    unsigned int buttons,
    unsigned char left_x,
    unsigned char left_y,
    unsigned char right_x,
    unsigned char right_y)
{
    std::lock_guard lock(pad::g_pad_mutex);
    const std::shared_ptr<Pad> target = get_or_create_ios_pad();
    if (!target || !target->ldd || !target->is_connected())
        return 0;

    CellPadData& state = target->ldd_data;
    state = {};
    state.button[0] = (buttons & kPS) ? CELL_PAD_CTRL_LDD_PS : 0;
    state.button[CELL_PAD_BTN_OFFSET_DIGITAL1] = digital1(buttons);
    state.button[CELL_PAD_BTN_OFFSET_DIGITAL2] = digital2(buttons);
    state.button[CELL_PAD_BTN_OFFSET_ANALOG_RIGHT_X] = right_x;
    state.button[CELL_PAD_BTN_OFFSET_ANALOG_RIGHT_Y] = right_y;
    state.button[CELL_PAD_BTN_OFFSET_ANALOG_LEFT_X] = left_x;
    state.button[CELL_PAD_BTN_OFFSET_ANALOG_LEFT_Y] = left_y;

    state.button[CELL_PAD_BTN_OFFSET_PRESS_RIGHT] = pressure(buttons, kRight);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_LEFT] = pressure(buttons, kLeft);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_UP] = pressure(buttons, kUp);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_DOWN] = pressure(buttons, kDown);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_TRIANGLE] = pressure(buttons, kTriangle);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_CIRCLE] = pressure(buttons, kCircle);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_CROSS] = pressure(buttons, kCross);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_SQUARE] = pressure(buttons, kSquare);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_L1] = pressure(buttons, kL1);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_R1] = pressure(buttons, kR1);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_L2] = pressure(buttons, kL2);
    state.button[CELL_PAD_BTN_OFFSET_PRESS_R2] = pressure(buttons, kR2);

    state.button[CELL_PAD_BTN_OFFSET_SENSOR_X] = DEFAULT_MOTION_X;
    state.button[CELL_PAD_BTN_OFFSET_SENSOR_Y] = DEFAULT_MOTION_Y;
    state.button[CELL_PAD_BTN_OFFSET_SENSOR_Z] = DEFAULT_MOTION_Z;
    state.button[CELL_PAD_BTN_OFFSET_SENSOR_G] = DEFAULT_MOTION_G;
    target->m_buffer_cleared = false;
    return 1;
}
