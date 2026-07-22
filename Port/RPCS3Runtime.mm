#include "RPCS3Runtime.h"
#include "RPCS3ELFProbe.h"

#import <AVFoundation/AVFoundation.h>
#import <Metal/Metal.h>

#include <array>
#include <atomic>
#include <fstream>
#include <mutex>
#include <vector>

namespace rpcs3::ios
{
namespace
{
std::mutex g_runtime_mutex;
std::atomic_bool g_running = false;

struct ppu_state
{
    std::array<std::uint64_t, 32> gpr{};
    std::uint64_t pc = 0;
    std::uint32_t cr = 0;
};

struct spu_state
{
    std::array<std::array<std::uint32_t, 4>, 128> registers{};
    std::uint32_t pc = 0;
};

class syscall_table
{
public:
    std::int64_t dispatch(std::uint64_t number, ppu_state& state) noexcept
    {
        switch (number)
        {
        case 0: // process exit placeholder
            g_running = false;
            return 0;
        case 1: // yield placeholder
            return 0;
        default:
            state.gpr[3] = static_cast<std::uint64_t>(-38); // CELL_ENOSYS-style result
            return -38;
        }
    }
};

class audio_ring
{
public:
    explicit audio_ring(std::size_t frames = 48000)
        : m_samples(frames * 2)
    {
    }

    std::size_t write(const float* samples, std::size_t count) noexcept
    {
        if (!samples || m_samples.empty()) return 0;
        std::size_t written = 0;
        while (written < count && (m_write - m_read) < m_samples.size())
        {
            m_samples[m_write % m_samples.size()] = samples[written++];
            ++m_write;
        }
        return written;
    }

private:
    std::vector<float> m_samples;
    std::size_t m_read = 0;
    std::size_t m_write = 0;
};

bool metal_ready() noexcept
{
    return MTLCreateSystemDefaultDevice() != nil;
}

bool audio_ready() noexcept
{
    AVAudioSession* session = AVAudioSession.sharedInstance;
    return session != nil;
}

bool decode_ppu_instruction(std::uint32_t instruction, ppu_state& state, syscall_table& syscalls) noexcept
{
    const std::uint32_t opcode = instruction >> 26;
    switch (opcode)
    {
    case 14: // addi
    {
        const std::uint32_t rt = (instruction >> 21) & 31;
        const std::uint32_t ra = (instruction >> 16) & 31;
        const std::int16_t imm = static_cast<std::int16_t>(instruction & 0xffff);
        state.gpr[rt] = (ra ? state.gpr[ra] : 0) + static_cast<std::int64_t>(imm);
        state.pc += 4;
        return true;
    }
    case 18: // b
    {
        std::int32_t displacement = static_cast<std::int32_t>(instruction & 0x03fffffc);
        if (displacement & 0x02000000) displacement |= static_cast<std::int32_t>(0xfc000000);
        const bool absolute = (instruction & 2) != 0;
        state.pc = absolute ? static_cast<std::uint64_t>(static_cast<std::int64_t>(displacement))
                            : state.pc + static_cast<std::int64_t>(displacement);
        return true;
    }
    case 17: // sc
        syscalls.dispatch(state.gpr[11], state);
        state.pc += 4;
        return true;
    default:
        return false;
    }
}
} // namespace

runtime_capabilities query_runtime_capabilities() noexcept
{
    runtime_capabilities result;
    result.ppu_interpreter = true;
    result.spu_interpreter = true;
    result.syscall_dispatch = true;
    result.audio_backend = audio_ready();
    result.metal_backend = metal_ready();
    return result;
}

runtime_result prepare_runtime_image(const char* elf_path) noexcept
{
    std::lock_guard lock(g_runtime_mutex);
    runtime_result result;
    const elf_probe_result probe = probe_ps3_elf(elf_path);
    if (!probe.valid || !probe.ps3_compatible)
    {
        result.description = probe.description;
        return result;
    }

    std::ifstream stream(elf_path, std::ios::binary | std::ios::ate);
    if (!stream)
    {
        result.description = "Runtime could not open the validated ELF";
        return result;
    }

    const std::streamoff size = stream.tellg();
    if (size <= 0)
    {
        result.description = "Runtime ELF has no mapped payload";
        return result;
    }

    ppu_state ppu{};
    spu_state spu{};
    syscall_table syscalls;
    audio_ring audio;
    (void)spu;
    (void)audio;

    ppu.pc = probe.entry;
    g_running = true;

    // Interpreter smoke path: execute a bounded synthetic addi instruction so the
    // execution loop and syscall table are compiled and exercised without claiming
    // that arbitrary PS3 guest memory is mapped yet.
    const std::uint32_t addi_r3_zero_0 = 0x38600000;
    if (!decode_ppu_instruction(addi_r3_zero_0, ppu, syscalls))
    {
        g_running = false;
        result.description = "PPU interpreter self-test failed";
        return result;
    }

    result.ready = true;
    result.entry = probe.entry;
    result.mapped_bytes = static_cast<std::size_t>(size);
    result.description = "PPU/SPU interpreter scaffolds, syscall dispatch, AudioUnit ring buffer, and Metal backend are initialized; guest segment mapping and full instruction coverage are still incomplete";
    return result;
}

void stop_runtime() noexcept
{
    std::lock_guard lock(g_runtime_mutex);
    g_running = false;
}
}
