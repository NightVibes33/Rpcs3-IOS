#include "stdafx.h"

#include "Input/pad_thread.h"
#include "Emu/Io/pad_types.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <thread>

namespace pad
{
atomic_t<pad_thread*> g_pad_thread = nullptr;
shared_mutex g_pad_mutex;
std::string g_title_id;
atomic_t<bool> g_enabled{true};
atomic_t<bool> g_reset{false};
atomic_t<bool> g_started{false};
atomic_t<bool> g_home_menu_requested{false};
}

pad_thread::pad_thread(void* curthread, void* curwindow, std::string_view title_id)
    : m_curthread(curthread)
    , m_curwindow(curwindow)
{
    pad::g_title_id = title_id;
    pad::g_pad_thread = this;

    for (u32 index = 0; index < CELL_PAD_MAX_PORT_NUM; ++index)
    {
        m_pads[index] = std::make_shared<Pad>(
            pad_handler::null,
            index,
            CELL_PAD_STATUS_DISCONNECTED,
            CELL_PAD_CAPABILITY_PS3_CONFORMITY | CELL_PAD_CAPABILITY_PRESS_MODE |
                CELL_PAD_CAPABILITY_SENSOR_MODE | CELL_PAD_CAPABILITY_ACTUATOR,
            CELL_PAD_DEV_TYPE_STANDARD);
    }
}

pad_thread::~pad_thread()
{
    pad::g_started = false;
    if (pad::g_pad_thread.observe() == this)
    {
        pad::g_pad_thread = nullptr;
    }
}

void pad_thread::operator()()
{
    // The iOS frontend supplies controller state through the LDD/cellPad bridge.
    // No desktop HID polling loop is needed, but the FXO-owned pad object remains
    // alive for the duration of emulation and is fully visible to cellPad.
    pad::g_started = true;
}

void pad_thread::Init()
{
    pad::g_started = true;
}

void pad_thread::InitLddPad(u32 handle, const u32* port_status)
{
    if (handle >= m_pads.size() || !m_pads[handle])
    {
        return;
    }

    auto& controller = m_pads[handle];
    controller->ldd = true;
    controller->Init(
        port_status ? *port_status
                    : CELL_PAD_STATUS_CONNECTED | CELL_PAD_STATUS_ASSIGN_CHANGES |
                          CELL_PAD_STATUS_CUSTOM_CONTROLLER,
        CELL_PAD_CAPABILITY_PS3_CONFORMITY | CELL_PAD_CAPABILITY_PRESS_MODE |
            CELL_PAD_CAPABILITY_SENSOR_MODE | CELL_PAD_CAPABILITY_ACTUATOR,
        CELL_PAD_DEV_TYPE_LDD,
        CELL_PAD_PCLASS_TYPE_STANDARD,
        0,
        0x054c,
        0x0268,
        50);
    ++num_ldd_pad;
    ++m_info.now_connect;
}

s32 pad_thread::AddLddPad()
{
    for (u32 index = 0; index < m_pads.size(); ++index)
    {
        if (m_pads[index] && !m_pads[index]->ldd)
        {
            InitLddPad(index, nullptr);
            return static_cast<s32>(index);
        }
    }
    return -1;
}

void pad_thread::UnregisterLddPad(u32 handle)
{
    if (handle >= m_pads.size() || !m_pads[handle] || !m_pads[handle]->ldd)
    {
        return;
    }

    auto& controller = m_pads[handle];
    controller->ldd = false;
    controller->m_port_status &= ~CELL_PAD_STATUS_CONNECTED;
    controller->m_port_status |= CELL_PAD_STATUS_ASSIGN_CHANGES;
    if (num_ldd_pad)
    {
        --num_ldd_pad;
    }
    if (m_info.now_connect)
    {
        --m_info.now_connect;
    }
}

void pad_thread::SetIntercepted(bool intercepted)
{
    if (intercepted)
    {
        m_info.system_info |= CELL_PAD_INFO_INTERCEPTED;
        m_info.ignore_input = true;
    }
    else
    {
        m_info.system_info &= ~CELL_PAD_INFO_INTERCEPTED;
        m_info.ignore_input = false;
    }
}

void pad_thread::SetRumble(u32 index, u8 large_motor, u8 small_motor)
{
    if (index >= m_pads.size() || !m_pads[index])
    {
        return;
    }
    m_pads[index]->m_vibrate_motors[0].value = large_motor;
    m_pads[index]->m_vibrate_motors[1].value = small_motor;
}

void qt_events_aware_op(int repeat_duration_ms, std::function<bool()> wrapped_op)
{
    if (!wrapped_op)
    {
        return;
    }

    while (!wrapped_op())
    {
        if (repeat_duration_ms > 0)
        {
            std::this_thread::sleep_for(std::chrono::milliseconds(repeat_duration_ms));
        }
        else
        {
            std::this_thread::yield();
        }
    }
}

[[noreturn]] void report_fatal_error(std::string_view text, bool, bool)
{
    std::fwrite("RPCS3 iOS fatal error: ", 1, 23, stderr);
    std::fwrite(text.data(), 1, text.size(), stderr);
    std::fwrite("\n", 1, 1, stderr);
    std::fflush(stderr);
    std::abort();
}
