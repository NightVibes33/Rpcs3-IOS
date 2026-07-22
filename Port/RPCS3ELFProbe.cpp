#include "RPCS3ELFProbe.h"

#include "rpcs3/Loader/ELF.h"

#include <array>
#include <fstream>
#include <sstream>

namespace rpcs3::ios
{
elf_probe_result probe_ps3_elf(const char* path) noexcept
{
    elf_probe_result result;
    if (!path || !*path)
    {
        result.description = "No ELF path supplied";
        return result;
    }

    std::ifstream stream(path, std::ios::binary);
    if (!stream)
    {
        result.description = "Unable to open ELF";
        return result;
    }

    using header_type = elf_ehdr<elf_be, u64>;
    header_type header{};
    stream.read(reinterpret_cast<char*>(&header), static_cast<std::streamsize>(sizeof(header)));
    if (stream.gcount() != static_cast<std::streamsize>(sizeof(header)))
    {
        result.description = "ELF64 header is truncated";
        return result;
    }

    const auto* magic = reinterpret_cast<const unsigned char*>(&header.e_magic);
    if (magic[0] != 0x7f || magic[1] != 'E' || magic[2] != 'L' || magic[3] != 'F')
    {
        result.description = "ELF magic is invalid";
        return result;
    }

    if (header.e_class != 2)
    {
        result.description = "RPCS3 requires an ELF64 image";
        return result;
    }

    if (header.e_data != 2)
    {
        result.description = "PS3 ELF images must be big-endian";
        return result;
    }

    if (header.e_curver != 1 || static_cast<u32>(header.e_version) != 1)
    {
        result.description = "Unsupported ELF version";
        return result;
    }

    result.valid = true;
    result.entry = static_cast<u64>(header.e_entry);
    result.program_header_count = static_cast<u16>(header.e_phnum);
    result.section_header_count = static_cast<u16>(header.e_shnum);

    const elf_machine machine = static_cast<elf_machine>(header.e_machine);
    const elf_type type = static_cast<elf_type>(header.e_type);
    const bool machine_ok = machine == elf_machine::ppc64;
    const bool type_ok = type == elf_type::exec || type == elf_type::prx;
    const bool os_ok = header.e_os_abi == elf_os::lv2 || header.e_os_abi == elf_os::none;
    result.ps3_compatible = machine_ok && type_ok && os_ok;

    std::ostringstream description;
    description << "ELF64 BE machine=0x" << std::hex << static_cast<unsigned>(static_cast<u16>(machine))
                << " type=0x" << static_cast<unsigned>(static_cast<u16>(type))
                << " entry=0x" << result.entry
                << std::dec << " ph=" << result.program_header_count
                << " sh=" << result.section_header_count;
    if (!result.ps3_compatible)
    {
        description << " (not a supported PS3 PPU executable)";
    }
    result.description = description.str();
    return result;
}
} // namespace rpcs3::ios
