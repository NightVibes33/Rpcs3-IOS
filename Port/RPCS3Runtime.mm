#include "RPCS3Runtime.h"
#include "RPCS3ELFProbe.h"

// EXPERIMENTAL, NON-SHIPPING LEGACY SCAFFOLD
//
// This file is intentionally excluded from rpcs3_ios_core. It must not be used
// to claim PPU, SPU, syscall, audio, Metal, or game-execution capability. The
// roadmap requires those systems to come from upstream RPCS3 implementation
// files and real platform backends.

namespace rpcs3::ios
{
runtime_capabilities query_runtime_capabilities() noexcept
{
    return {};
}

runtime_result prepare_runtime_image(const char* elf_path) noexcept
{
    runtime_result result;
    const elf_probe_result probe = probe_ps3_elf(elf_path);
    if (!probe.valid || !probe.ps3_compatible)
    {
        result.description = probe.description;
        return result;
    }

    result.entry = probe.entry;
    result.description =
        "Legacy synthetic runtime is disabled. The file was only validated; "
        "guest execution requires the upstream RPCS3 Emu.System, VM, PPU, SPU, "
        "LV2, and renderer paths.";
    return result;
}

void stop_runtime() noexcept
{
}
} // namespace rpcs3::ios
