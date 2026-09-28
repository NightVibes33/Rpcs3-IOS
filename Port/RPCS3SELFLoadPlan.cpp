#include "RPCS3SELFLoadPlan.h"
#include "RPCS3SELFProbe.h"

#include <array>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>

namespace rpcs3::ios
{
namespace
{
std::uint16_t be16(const unsigned char* p)
{
    return static_cast<std::uint16_t>((p[0] << 8) | p[1]);
}

std::uint32_t be32(const unsigned char* p)
{
    return (static_cast<std::uint32_t>(p[0]) << 24) |
           (static_cast<std::uint32_t>(p[1]) << 16) |
           (static_cast<std::uint32_t>(p[2]) << 8) |
           static_cast<std::uint32_t>(p[3]);
}

std::uint64_t be64(const unsigned char* p)
{
    std::uint64_t value = 0;
    for (int i = 0; i < 8; ++i)
        value = (value << 8) | p[i];
    return value;
}

bool fits(std::uint64_t offset, std::uint64_t size, std::uint64_t limit)
{
    return offset <= limit && size <= limit - offset;
}

bool read_exact(std::ifstream& stream, std::uint64_t offset, void* output, std::size_t size)
{
    if (offset > static_cast<std::uint64_t>(std::numeric_limits<std::streamoff>::max()))
        return false;
    stream.clear();
    stream.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!stream)
        return false;
    stream.read(static_cast<char*>(output), static_cast<std::streamsize>(size));
    return stream.gcount() == static_cast<std::streamsize>(size);
}
} // namespace

self_load_plan build_plain_self_load_plan(const char* path) noexcept
{
    self_load_plan plan;
    const self_probe_result probe = probe_ps3_self(path);
    if (!probe.structurally_valid)
    {
        plan.description = probe.description;
        return plan;
    }
    if (probe.requires_decryption || probe.compressed_segment_count != 0)
    {
        plan.description = "SELF segment mapping is blocked by encrypted or compressed data";
        return plan;
    }
    if (!probe.contains_plain_elf || probe.segment_count == 0)
    {
        plan.description = "SELF does not expose a plain ELF64 program layout";
        return plan;
    }

    std::error_code ec;
    const std::uint64_t file_size = std::filesystem::file_size(path, ec);
    if (ec)
    {
        plan.description = "Unable to query SELF size";
        return plan;
    }

    std::ifstream stream(path, std::ios::binary);
    std::array<unsigned char, 0x50> ext{};
    if (!read_exact(stream, 0x20, ext.data(), ext.size()))
    {
        plan.description = "Unable to read SELF extended header";
        return plan;
    }

    const std::uint64_t phdr_offset = be64(ext.data() + 24);
    constexpr std::uint64_t phdr_size = 0x38;
    constexpr std::uint64_t segment_ext_size = 0x20;
    const std::uint64_t phdr_bytes = static_cast<std::uint64_t>(probe.segment_count) * phdr_size;
    const std::uint64_t segment_bytes = static_cast<std::uint64_t>(probe.segment_count) * segment_ext_size;
    if (!fits(phdr_offset, phdr_bytes, file_size) ||
        !fits(probe.segment_table_offset, segment_bytes, file_size))
    {
        plan.description = "SELF program or segment table exceeds the imported file";
        return plan;
    }

    std::array<unsigned char, 0x40> elf{};
    if (!read_exact(stream, probe.elf_offset, elf.data(), elf.size()))
    {
        plan.description = "Unable to read embedded ELF64 header";
        return plan;
    }
    plan.entry = be64(elf.data() + 24);

    plan.segments.reserve(probe.segment_count);
    for (std::uint32_t index = 0; index < probe.segment_count; ++index)
    {
        std::array<unsigned char, phdr_size> phdr{};
        std::array<unsigned char, segment_ext_size> segment{};
        if (!read_exact(stream, phdr_offset + index * phdr_size, phdr.data(), phdr.size()) ||
            !read_exact(stream, probe.segment_table_offset + index * segment_ext_size, segment.data(), segment.size()))
        {
            plan.description = "Unable to read a SELF program mapping";
            return plan;
        }

        const std::uint64_t source_offset = be64(segment.data());
        const std::uint64_t source_size = be64(segment.data() + 8);
        const std::uint32_t compression = be32(segment.data() + 16);
        const std::uint64_t encryption = be64(segment.data() + 24);
        if (compression != 1 || encryption == 2 || !fits(source_offset, source_size, file_size))
        {
            plan.description = "SELF contains a segment that is not plain and directly mappable";
            return plan;
        }

        self_segment_mapping mapping;
        mapping.flags = be32(phdr.data() + 4);
        mapping.elf_file_offset = be64(phdr.data() + 8);
        mapping.virtual_address = be64(phdr.data() + 16);
        mapping.source_offset = source_offset;
        mapping.source_size = source_size;
        mapping.memory_size = be64(phdr.data() + 40);
        if (mapping.source_size > mapping.memory_size)
        {
            plan.description = "SELF segment file size exceeds its ELF memory size";
            return plan;
        }
        plan.segments.push_back(mapping);
    }

    plan.valid = true;
    plan.ready_for_plain_extraction = true;
    std::ostringstream text;
    text << "Plain SELF load plan entry=0x" << std::hex << plan.entry << std::dec
         << ", mapped segments=" << plan.segments.size();
    plan.description = text.str();
    return plan;
}
} // namespace rpcs3::ios
