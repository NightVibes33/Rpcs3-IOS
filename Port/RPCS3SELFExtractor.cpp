#include "RPCS3SELFExtractor.h"
#include "RPCS3SELFLoadPlan.h"
#include "RPCS3SELFProbe.h"

#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <limits>
#include <sstream>
#include <vector>

namespace rpcs3::ios
{
namespace
{
bool fits(std::uint64_t offset, std::uint64_t size, std::uint64_t limit)
{
    return offset <= limit && size <= limit - offset;
}

bool read_exact(std::ifstream& input, std::uint64_t offset, void* output, std::size_t size)
{
    if (offset > static_cast<std::uint64_t>(std::numeric_limits<std::streamoff>::max()))
        return false;
    input.clear();
    input.seekg(static_cast<std::streamoff>(offset), std::ios::beg);
    if (!input)
        return false;
    input.read(static_cast<char*>(output), static_cast<std::streamsize>(size));
    return input.gcount() == static_cast<std::streamsize>(size);
}

bool copy_range(std::ifstream& input, std::ofstream& output,
                std::uint64_t source_offset, std::uint64_t destination_offset,
                std::uint64_t size)
{
    if (source_offset > static_cast<std::uint64_t>(std::numeric_limits<std::streamoff>::max()) ||
        destination_offset > static_cast<std::uint64_t>(std::numeric_limits<std::streamoff>::max()))
        return false;

    input.clear();
    input.seekg(static_cast<std::streamoff>(source_offset), std::ios::beg);
    output.clear();
    output.seekp(static_cast<std::streamoff>(destination_offset), std::ios::beg);
    if (!input || !output)
        return false;

    std::array<char, 64 * 1024> buffer{};
    std::uint64_t remaining = size;
    while (remaining != 0)
    {
        const std::size_t chunk = static_cast<std::size_t>(
            remaining < buffer.size() ? remaining : buffer.size());
        input.read(buffer.data(), static_cast<std::streamsize>(chunk));
        if (input.gcount() != static_cast<std::streamsize>(chunk))
            return false;
        output.write(buffer.data(), static_cast<std::streamsize>(chunk));
        if (!output)
            return false;
        remaining -= chunk;
    }
    return true;
}
} // namespace

self_extraction_result extract_plain_self_to_elf(
    const char* self_path,
    const char* output_path) noexcept
{
    self_extraction_result result;
    if (!self_path || !*self_path || !output_path || !*output_path)
    {
        result.description = "SELF extraction requires input and output paths";
        return result;
    }

    const self_probe_result probe = probe_ps3_self(self_path);
    const self_load_plan plan = build_plain_self_load_plan(self_path);
    if (!probe.structurally_valid || !plan.valid || !plan.ready_for_plain_extraction)
    {
        result.description = plan.description.empty() ? probe.description : plan.description;
        return result;
    }

    std::error_code ec;
    const std::uint64_t input_size = std::filesystem::file_size(self_path, ec);
    if (ec)
    {
        result.description = "Unable to query SELF size for extraction";
        return result;
    }

    std::uint64_t output_size = 0x40;
    for (const self_segment_mapping& segment : plan.segments)
    {
        if (!fits(segment.source_offset, segment.source_size, input_size))
        {
            result.description = "SELF segment changed after validation";
            return result;
        }
        if (segment.elf_file_offset > std::numeric_limits<std::uint64_t>::max() - segment.source_size)
        {
            result.description = "ELF output range overflows";
            return result;
        }
        const std::uint64_t end = segment.elf_file_offset + segment.source_size;
        if (end > output_size)
            output_size = end;
    }

    // Keep reconstruction bounded to a practical iOS cache artifact.
    constexpr std::uint64_t maximum_output_size = 4ull * 1024ull * 1024ull * 1024ull;
    if (output_size == 0 || output_size > maximum_output_size)
    {
        result.description = "Reconstructed ELF size is outside the supported bound";
        return result;
    }

    const std::filesystem::path destination(output_path);
    std::filesystem::create_directories(destination.parent_path(), ec);
    if (ec)
    {
        result.description = "Unable to create the SELF extraction cache directory";
        return result;
    }

    const std::filesystem::path temporary = destination.string() + ".tmp";
    std::filesystem::remove(temporary, ec);
    ec.clear();

    std::ifstream input(self_path, std::ios::binary);
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    if (!input || !output)
    {
        result.description = "Unable to open SELF extraction streams";
        return result;
    }

    // Copy the embedded ELF64 header and program-header table from the SELF header.
    std::array<unsigned char, 0x50> ext{};
    if (!read_exact(input, 0x20, ext.data(), ext.size()))
    {
        result.description = "Unable to read SELF extended header during extraction";
        return result;
    }
    auto be64 = [](const unsigned char* p) {
        std::uint64_t value = 0;
        for (int i = 0; i < 8; ++i)
            value = (value << 8) | p[i];
        return value;
    };
    const std::uint64_t phdr_offset = be64(ext.data() + 24);
    constexpr std::uint64_t elf_header_size = 0x40;
    constexpr std::uint64_t phdr_size = 0x38;
    const std::uint64_t phdr_bytes = static_cast<std::uint64_t>(plan.segments.size()) * phdr_size;

    if (!copy_range(input, output, probe.elf_offset, 0, elf_header_size) ||
        !copy_range(input, output, phdr_offset, elf_header_size, phdr_bytes))
    {
        result.description = "Unable to copy embedded ELF headers";
        return result;
    }

    for (const self_segment_mapping& segment : plan.segments)
    {
        if (!copy_range(input, output, segment.source_offset,
                        segment.elf_file_offset, segment.source_size))
        {
            result.description = "Unable to copy a plain SELF segment";
            return result;
        }
    }

    if (output_size != 0)
    {
        output.seekp(static_cast<std::streamoff>(output_size - 1), std::ios::beg);
        const char zero = 0;
        output.write(&zero, 1);
    }
    output.flush();
    output.close();
    if (!output)
    {
        result.description = "Unable to finalize the reconstructed ELF";
        return result;
    }

    std::filesystem::remove(destination, ec);
    ec.clear();
    std::filesystem::rename(temporary, destination, ec);
    if (ec)
    {
        std::filesystem::remove(temporary, ec);
        result.description = "Unable to publish the reconstructed ELF";
        return result;
    }

    result.success = true;
    result.output_path = destination.string();
    std::ostringstream text;
    text << "Reconstructed plain SELF into " << output_size
         << "-byte ELF with " << plan.segments.size() << " mapped segments";
    result.description = text.str();
    return result;
}
} // namespace rpcs3::ios
