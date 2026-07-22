#include "RPCS3CoreBridge.h"
#include "IOSFilesystem.h"
#include "IOSPlatform.h"

#ifdef RPCS3_IOS_WITH_UPSTREAM_CRYPTO
#include "sha256.h"
#endif

#include <array>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <utility>

namespace
{
std::mutex g_mutex;
bool g_platform_initialized = false;
RPCS3IOSCoreState g_state = RPCS3IOSCoreStateUnavailable;
std::string g_data_path;
std::string g_last_boot_sha256;
std::string g_message = "RPCS3 iOS platform has not been initialized.";

void set_failure(std::string message)
{
    g_state = RPCS3IOSCoreStateFailed;
    g_message = std::move(message);
}

#ifdef RPCS3_IOS_WITH_UPSTREAM_CRYPTO
std::string hex_encode(const unsigned char* bytes, std::size_t size)
{
    static constexpr char digits[] = "0123456789abcdef";
    std::string output;
    output.resize(size * 2);
    for (std::size_t index = 0; index < size; ++index)
    {
        output[index * 2] = digits[bytes[index] >> 4];
        output[index * 2 + 1] = digits[bytes[index] & 0x0f];
    }
    return output;
}

bool sha256_bytes(const unsigned char* bytes, std::size_t size, std::string& output)
{
    std::array<unsigned char, 32> digest{};
    if (mbedtls_sha256_ret(bytes, size, digest.data(), 0) != 0)
    {
        return false;
    }
    output = hex_encode(digest.data(), digest.size());
    return true;
}

bool sha256_file(std::ifstream& stream, std::string& output)
{
    mbedtls_sha256_context context{};
    mbedtls_sha256_init(&context);
    if (mbedtls_sha256_starts_ret(&context, 0) != 0)
    {
        mbedtls_sha256_free(&context);
        return false;
    }

    stream.clear();
    stream.seekg(0, std::ios::beg);
    std::array<unsigned char, 64 * 1024> buffer{};
    while (stream)
    {
        stream.read(reinterpret_cast<char*>(buffer.data()), static_cast<std::streamsize>(buffer.size()));
        const std::streamsize count = stream.gcount();
        if (count > 0 && mbedtls_sha256_update_ret(
                &context, buffer.data(), static_cast<std::size_t>(count)) != 0)
        {
            mbedtls_sha256_free(&context);
            return false;
        }
    }

    if (stream.bad())
    {
        mbedtls_sha256_free(&context);
        return false;
    }

    std::array<unsigned char, 32> digest{};
    const int status = mbedtls_sha256_finish_ret(&context, digest.data());
    mbedtls_sha256_free(&context);
    if (status != 0)
    {
        return false;
    }

    output = hex_encode(digest.data(), digest.size());
    return true;
}

bool upstream_crypto_self_test()
{
    static constexpr unsigned char payload[] = {'a', 'b', 'c'};
    static constexpr const char* expected =
        "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad";
    std::string digest;
    return sha256_bytes(payload, sizeof(payload), digest) && digest == expected;
}
#endif
} // namespace

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void)
{
    const rpcs3::ios::platform_capabilities capabilities =
        rpcs3::ios::query_platform_capabilities();

    thread_local std::string message_copy;
    thread_local std::string path_copy;
    thread_local std::string hash_copy;

    std::lock_guard lock(g_mutex);
    message_copy = g_message;
    path_copy = g_data_path;
    hash_copy = g_last_boot_sha256;

    RPCS3IOSCoreDiagnostics result = {};
    result.state = g_state;
    result.platform_initialized = g_platform_initialized ? 1 : 0;
#ifdef RPCS3_IOS_WITH_UPSTREAM_CRYPTO
    result.upstream_crypto_available = 1;
#else
    result.upstream_crypto_available = 0;
#endif
    result.ppu_interpreter_available = 0;
    result.spu_interpreter_available = 0;
    result.jit_available = capabilities.dynamic_code_supported ? 1 : 0;
    result.renderer_available = capabilities.metal_available ? 1 : 0;
    result.data_path = path_copy.empty() ? nullptr : path_copy.c_str();
    result.last_boot_sha256 = hash_copy.empty() ? nullptr : hash_copy.c_str();
    result.message = message_copy.c_str();
    return result;
}

int rpcs3_ios_core_initialize(const char *data_path)
{
    std::lock_guard lock(g_mutex);

    const rpcs3::ios::filesystem_layout layout =
        rpcs3::ios::prepare_filesystem_layout(data_path);
    if (!layout.ready)
    {
        g_platform_initialized = false;
        set_failure(layout.error.empty() ? "Unable to prepare RPCS3 sandbox storage" : layout.error);
        return 0;
    }

    const rpcs3::ios::platform_capabilities capabilities =
        rpcs3::ios::query_platform_capabilities();
    if (!capabilities.physical_device)
    {
        g_platform_initialized = false;
        set_failure("RPCS3 iOS requires a physical arm64 iOS device");
        return 0;
    }

#ifdef RPCS3_IOS_WITH_UPSTREAM_CRYPTO
    if (!upstream_crypto_self_test())
    {
        g_platform_initialized = false;
        set_failure("Upstream RPCS3 SHA-256 self-test failed");
        return 0;
    }
#endif

    g_platform_initialized = true;
    g_data_path = layout.root;
    g_last_boot_sha256.clear();
    g_state = RPCS3IOSCoreStateUnavailable;
#ifdef RPCS3_IOS_WITH_UPSTREAM_CRYPTO
    g_message = capabilities.metal_available
        ? "Sandbox storage, Metal, and upstream RPCS3 SHA-256 are ready. PPU/SPU execution is not linked yet."
        : "Sandbox storage and upstream RPCS3 SHA-256 are ready, but no Metal device is available.";
#else
    g_message = capabilities.metal_available
        ? "Sandbox storage and Metal are ready. The upstream RPCS3 interpreter core is not linked yet."
        : "Sandbox storage is ready, but no Metal device is available.";
#endif
    return 1;
}

int rpcs3_ios_core_boot_elf(const char *elf_path)
{
    std::lock_guard lock(g_mutex);

    if (!g_platform_initialized)
    {
        set_failure("Initialize the iOS platform before loading an ELF");
        return 0;
    }

    if (!elf_path || !*elf_path)
    {
        set_failure("No ELF path was supplied");
        return 0;
    }

    if (!rpcs3::ios::path_is_within_app_container(elf_path))
    {
        set_failure("Boot input must be copied into the RPCS3 app container first");
        return 0;
    }

    std::error_code filesystem_error;
    if (!std::filesystem::is_regular_file(elf_path, filesystem_error))
    {
        set_failure("Boot input is not a readable regular file");
        return 0;
    }

    std::ifstream stream(elf_path, std::ios::binary);
    std::array<unsigned char, 4> magic{};
    stream.read(reinterpret_cast<char*>(magic.data()), static_cast<std::streamsize>(magic.size()));
    if (stream.gcount() != static_cast<std::streamsize>(magic.size()) ||
        magic[0] != 0x7f || magic[1] != 'E' || magic[2] != 'L' || magic[3] != 'F')
    {
        set_failure("Boot input does not contain an ELF header");
        return 0;
    }

#ifdef RPCS3_IOS_WITH_UPSTREAM_CRYPTO
    if (!sha256_file(stream, g_last_boot_sha256))
    {
        set_failure("Unable to calculate the boot ELF SHA-256");
        return 0;
    }
    g_message = "ELF header and SHA-256 validated inside the app sandbox; interpreter execution is not linked yet.";
#else
    g_last_boot_sha256.clear();
    g_message = "ELF header validated inside the app sandbox; interpreter execution is not linked yet.";
#endif
    g_state = RPCS3IOSCoreStateUnavailable;
    return 0;
}

void rpcs3_ios_core_stop(void)
{
    std::lock_guard lock(g_mutex);
    if (g_platform_initialized)
    {
        g_state = RPCS3IOSCoreStateStopped;
        g_message = "Core stop requested; no upstream execution engine is linked.";
    }
}
