#include <cstddef>

// RPCS3's bundled SHA-256 implementation calls this helper from Crypto/utils.h.
// Keep the fallback local to the iOS core-only target until the complete crypto
// utility translation unit is portable on iPhoneOS.
void mbedtls_zeroize(void* value, std::size_t size)
{
    volatile unsigned char* cursor = static_cast<volatile unsigned char*>(value);
    while (size-- > 0)
    {
        *cursor++ = 0;
    }
}
