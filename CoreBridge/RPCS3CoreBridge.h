#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum RPCS3IOSCoreState {
    RPCS3IOSCoreStateUnavailable = 0,
    RPCS3IOSCoreStateReady = 1,
    RPCS3IOSCoreStateRunning = 2,
    RPCS3IOSCoreStateStopped = 3,
    RPCS3IOSCoreStateFailed = 4
} RPCS3IOSCoreState;

typedef enum RPCS3IOSCoreCapabilityLevel {
    RPCS3IOSCoreCapabilityProbeOnly = 0,
    RPCS3IOSCoreCapabilityPartialUpstream = 1,
    RPCS3IOSCoreCapabilityExecutionCapable = 2
} RPCS3IOSCoreCapabilityLevel;

typedef enum RPCS3IOSCorePadButton {
    RPCS3IOSCorePadUp       = 1u << 0,
    RPCS3IOSCorePadDown     = 1u << 1,
    RPCS3IOSCorePadLeft     = 1u << 2,
    RPCS3IOSCorePadRight    = 1u << 3,
    RPCS3IOSCorePadCross    = 1u << 4,
    RPCS3IOSCorePadCircle   = 1u << 5,
    RPCS3IOSCorePadSquare   = 1u << 6,
    RPCS3IOSCorePadTriangle = 1u << 7,
    RPCS3IOSCorePadL1       = 1u << 8,
    RPCS3IOSCorePadR1       = 1u << 9,
    RPCS3IOSCorePadL2       = 1u << 10,
    RPCS3IOSCorePadR2       = 1u << 11,
    RPCS3IOSCorePadL3       = 1u << 12,
    RPCS3IOSCorePadR3       = 1u << 13,
    RPCS3IOSCorePadStart    = 1u << 14,
    RPCS3IOSCorePadSelect   = 1u << 15,
    RPCS3IOSCorePadPS       = 1u << 16
} RPCS3IOSCorePadButton;

typedef struct RPCS3IOSCoreDiagnostics {
    RPCS3IOSCoreState state;
    RPCS3IOSCoreCapabilityLevel capability_level;
    int platform_initialized;
    int upstream_crypto_available;
    int upstream_source_count;
    int ppu_interpreter_available;
    int spu_interpreter_available;
    int jit_available;
    int renderer_available;
    int firmware_ready;
    const char *upstream_revision;
    const char *build_classification;
    const char *data_path;
    const char *firmware_version;
    const char *last_boot_sha256;
    const char *message;
} RPCS3IOSCoreDiagnostics;

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void);
int rpcs3_ios_core_initialize(const char *data_path);
int rpcs3_ios_core_set_render_view(void *native_view);
void rpcs3_ios_core_clear_render_view(void);
int rpcs3_ios_core_install_firmware(const char *pup_path);
int rpcs3_ios_core_firmware_ready(void);
const char *rpcs3_ios_core_firmware_version(void);
int rpcs3_ios_core_install_pkg(const char *pkg_path);
const char *rpcs3_ios_core_last_installed_boot_path(void);
int rpcs3_ios_core_boot_elf(const char *boot_path);
int rpcs3_ios_core_set_pad_state(
    unsigned int buttons,
    unsigned char left_x,
    unsigned char left_y,
    unsigned char right_x,
    unsigned char right_y);
void rpcs3_ios_core_stop(void);

#ifdef __cplusplus
}
#endif
