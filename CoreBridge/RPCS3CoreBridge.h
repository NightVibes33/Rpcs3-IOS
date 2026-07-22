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
    const char *upstream_revision;
    const char *build_classification;
    const char *data_path;
    const char *last_boot_sha256;
    const char *message;
} RPCS3IOSCoreDiagnostics;

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void);
int rpcs3_ios_core_initialize(const char *data_path);
int rpcs3_ios_core_install_pkg(const char *pkg_path);
const char *rpcs3_ios_core_last_installed_boot_path(void);
int rpcs3_ios_core_boot_elf(const char *boot_path);
void rpcs3_ios_core_stop(void);

#ifdef __cplusplus
}
#endif
