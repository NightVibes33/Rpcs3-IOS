#include "RPCS3SELFProbe.h"

#include <array>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace rpcs3::ios
{
namespace
{
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
    stream.read(reinterpret_cast<char*>(header.data()), static_cast<std::streamsize>(header.size()));
    if (stream.gcount() != static_cast<std::streamsize>(header.size()))
    {
        result.description = "Unable to read the PS3 SELF header";
        return result;
    }

    // SCE container magic: 0x53434500 ("SCE\\0").
    if (read_be32(header.data()) != 0x53434500u)
    {
        result.description = "Input is not an SCE/SELF container";
        return result;
    }

    result.recognized = true;
    const std::uint32_t version = read_be32(header.data() + 4);
    const std::uint16_t header_type = static_cast<std::uint16_t>((header[8] << 8) | header[9]);
    const std::uint64_t metadata_offset = read_be32(header.data() + 12);
    const std::uint64_t header_length = read_be64(header.data() + 16);
    const std::uint64_t data_length = read_be64(header.data() + 24);

    if (version == 0 || header_length < header.size() || header_length > result.file_size)
    {
        result.description = "SELF header length is outside the imported file";
        return result;
    }
    if (metadata_offset >= header_length)
    {
        result.description = "SELF metadata offset is outside the declared header";
        return result;
    }
    if (data_length > result.file_size || header_length > result.file_size - data_length)
    {
        result.description = "SELF data range exceeds the imported file";
        return result;
    }

    // A decrypted/debug SELF commonly exposes the embedded ELF at the declared header boundary.
    result.elf_offset = header_length;
    if (result.elf_offset + 4 <= result.file_size)
    {
        std::array<unsigned char, 4> magic{};
        stream.clear();
        stream.seekg(static_cast<std::streamoff>(result.elf_offset), std::ios::beg);
        stream.read(reinterpret_cast<char*>(magic.data()), static_cast<std::streamsize>(magic.size()));
        result.contains_plain_elf = stream.gcount() == static_cast<std::streamsize>(magic.size()) &&
            magic[0] == 0x7f && magic[1] == 'E' && magic[2] == 'L' && magic[3] == 'F';
    }

    result.structurally_valid = true;
    std::ostringstream description;
    description << "PS3 SELF container v" << version
                << ", type 0x" << std::hex << header_type << std::dec
                << ", header " << header_length << " bytes"
                << ", payload " << data_length << " bytes";
    description << (result.contains_plain_elf
        ? "; embedded plain ELF detected"
        : "; encrypted/compressed payload requires upstream SELF decryption");
    result.description = description.str();
    return result;
}
} // namespace rpcs3::ios
