#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum RPCS3AppleMobilePadButton
{
    RPCS3AppleMobilePadUp       = 0x00001u,
    RPCS3AppleMobilePadDown     = 0x00002u,
    RPCS3AppleMobilePadLeft     = 0x00004u,
    RPCS3AppleMobilePadRight    = 0x00008u,
    RPCS3AppleMobilePadCross    = 0x00010u,
    RPCS3AppleMobilePadCircle   = 0x00020u,
    RPCS3AppleMobilePadSquare   = 0x00040u,
    RPCS3AppleMobilePadTriangle = 0x00080u,
    RPCS3AppleMobilePadL1       = 0x00100u,
    RPCS3AppleMobilePadR1       = 0x00200u,
    RPCS3AppleMobilePadL2       = 0x00400u,
    RPCS3AppleMobilePadR2       = 0x00800u,
    RPCS3AppleMobilePadL3       = 0x01000u,
    RPCS3AppleMobilePadR3       = 0x02000u,
    RPCS3AppleMobilePadStart    = 0x04000u,
    RPCS3AppleMobilePadSelect   = 0x08000u,
    RPCS3AppleMobilePadPS       = 0x10000u,
} RPCS3AppleMobilePadButton;

typedef struct RPCS3AppleMobileDeviceProfile
{
    int is_ipad;
    int supports_hover;
    int supports_pencil;
    int maximum_frames_per_second;
    int active_processor_count;
    uint64_t physical_memory_bytes;
    uint64_t recommended_guest_memory_bytes;
} RPCS3AppleMobileDeviceProfile;

// Safe to call repeatedly. UIKit work is dispatched to the main queue.
void rpcs3_apple_mobile_initialize(void);
void rpcs3_apple_mobile_shutdown(void);

RPCS3AppleMobileDeviceProfile rpcs3_apple_mobile_device_profile(void);
const char* rpcs3_apple_mobile_application_support_path(void);
const char* rpcs3_apple_mobile_documents_path(void);

// RPCS3's API uses "enabled" to mean display sleep is allowed.
void rpcs3_apple_mobile_set_display_sleep_enabled(int enabled);
void rpcs3_apple_mobile_set_emulation_active(int active);
int rpcs3_apple_mobile_configure_audio_session(void);

// Runtime evidence checkpoints. The implementation writes JSONL into
// Library/Application Support/RPCS3/runtime/apple-mobile-runtime.jsonl.
void rpcs3_apple_mobile_log_checkpoint(const char* name, const char* detail);
void rpcs3_apple_mobile_mark_frame_presented(void);

#ifdef __cplusplus
}
#endif
