#include "RPCS3SELFProbe.h"

#include <array>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>
#include <vector>

namespace rpcs3::ios
{
namespace
{
std::uint16_t read_be16(const unsigned char* p)
{
    return static_cast<std::uint16_t>((p[0] << 8) | p[1]);
}

std::uint32_t read_be32(const unsigned char* p)
{
    return (static_cast<std::uint32_t>(p[0]) << 24) |
           (static_cast<std::uint32_t>(p[1]) << 16) |
           (static_cast<std::uint32_t>(p[2]) << 8) |
           static_cast<std::uint32_t>(p[3]);
}

std::uint64_t read_be64(const unsigned char* p)
{
    std::uint64_t value = 0;
    for (int i = 0; i < 8; ++i)
        value = (value << 8) | p[i];
    return value;
}

bool range_fits(std::uint64_t offset, std::uint64_t size, std::uint64_t limit)
{
    return offset <= limit && size <= limit - offset;
}

bool read_exact(std::ifstream& stream, std::uint64_t offset, unsigned char* output, std::size_t size)
{
    if (offset > static_cast<std::uint64_t>(std::numeric_limits<std::streamoff>::max()))
        return false;
    stream.clear();
    stream.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!stream)
        return false;
    stream.read(reinterpret_cast<char*>(output), static_cast<std::streamsize>(size));
    return stream.gcount() == static_cast<std::streamsize>(size);
}
} // namespace

self_probe_result probe_ps3_self(const char* path)
{
    self_probe_result result;
    if (!path || !*path)
    {
        result.description = "No SELF path was supplied";
        return result;
    }

    std::error_code ec;
    result.file_size = std::filesystem::file_size(path, ec);
    if (ec || result.file_size < 0x20)
    {
        result.description = "Input is too small to contain a PS3 SELF header";
        return result;
    }

    std::ifstream stream(path, std::ios::binary);
    std::array<unsigned char, 0x20> header{};
    if (!read_exact(stream, 0, header.data(), header.size()))
    {
        result.description = "Unable to read the PS3 SELF header";
        return result;
    }

    if (read_be32(header.data()) != 0x53434500u)
    {
        result.description = "Input is not an SCE/SELF container";
        return result;
    }

    result.recognized = true;
    const std::uint32_t version = read_be32(header.data() + 4);
    const std::uint16_t header_type = read_be16(header.data() + 10);
    result.metadata_offset = read_be32(header.data() + 12);
    const std::uint64_t header_length = read_be64(header.data() + 16);
    const std::uint64_t data_length = read_be64(header.data() + 24);

    if (version == 0 || header_length < header.size() || header_length > result.file_size)
    {
        result.description = "SELF header length is outside the imported file";
        return result;
    }
    if (result.metadata_offset >= header_length)
    {
        result.description = "SELF metadata offset is outside the declared header";
        return result;
    }
    if (data_length > result.file_size || header_length > result.file_size - data_length)
    {
        result.description = "SELF data range exceeds the imported file";
        return result;
    }

    // RPCS3's upstream ext_hdr follows the 0x20-byte SCE header and contains
    // offsets for the embedded ELF header and segment extension table.
    std::array<unsigned char, 0x50> ext{};
    if (!range_fits(0x20, ext.size(), header_length) || !read_exact(stream, 0x20, ext.data(), ext.size()))
    {
        result.description = "SELF extended header is truncated";
        return result;
    }

    result.elf_offset = read_be64(ext.data() + 16);
    result.segment_table_offset = read_be64(ext.data() + 40);

    if (!range_fits(result.elf_offset, 0x40, header_length))
    {
        result.description = "SELF embedded ELF header offset is outside the declared header";
        return result;
    }

    std::array<unsigned char, 0x40> elf_header{};
    if (!read_exact(stream, result.elf_offset, elf_header.data(), elf_header.size()))
    {
        result.description = "Unable to read the SELF embedded ELF header";
        return result;
    }

    result.contains_plain_elf = elf_header[0] == 0x7f && elf_header[1] == 'E' &&
        elf_header[2] == 'L' && elf_header[3] == 'F';

    if (result.contains_plain_elf && elf_header[4] == 2 && elf_header[5] == 2)
        result.segment_count = read_be16(elf_header.data() + 56);

    constexpr std::uint64_t segment_entry_size = 0x20;
    if (result.segment_count > 0)
    {
        const std::uint64_t table_size = static_cast<std::uint64_t>(result.segment_count) * segment_entry_size;
        if (!range_fits(result.segment_table_offset, table_size, header_length))
        {
            result.description = "SELF segment extension table exceeds the declared header";
            return result;
        }

        std::vector<unsigned char> table(static_cast<std::size_t>(table_size));
        if (!read_exact(stream, result.segment_table_offset, table.data(), table.size()))
        {
            result.description = "Unable to read the SELF segment extension table";
            return result;
        }

        for (std::uint32_t index = 0; index < result.segment_count; ++index)
        {
            const unsigned char* entry = table.data() + static_cast<std::size_t>(index) * segment_entry_size;
            const std::uint64_t data_offset = read_be64(entry);
            const std::uint64_t data_size = read_be64(entry + 8);
            const std::uint32_t compression = read_be32(entry + 16);
            const std::uint64_t encryption = read_be64(entry + 24);

            if (!range_fits(data_offset, data_size, result.file_size))
            {
                result.description = "SELF segment data range exceeds the imported file";
                return result;
            }
            if (compression == 2)
                ++result.compressed_segment_count;
            if (encryption == 2)
                ++result.encrypted_segment_count;
        }
        result.metadata_layout_valid = true;
    }

    result.requires_decryption = result.encrypted_segment_count > 0 || !result.contains_plain_elf;
    result.structurally_valid = true;

    std::ostringstream description;
    description << "PS3 SELF container v" << version
                << ", type 0x" << std::hex << header_type << std::dec
                << ", header " << header_length << " bytes"
                << ", payload " << data_length << " bytes"
                << ", segments " << result.segment_count
                << " (encrypted " << result.encrypted_segment_count
                << ", compressed " << result.compressed_segment_count << ")";
    description << (result.requires_decryption
        ? "; upstream key selection/decryption is required"
        : "; plain segment layout is ready for extraction");
    result.description = description.str();
    return result;
}
} // namespace rpcs3::ios
