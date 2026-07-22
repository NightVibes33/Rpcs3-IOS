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

typedef enum RPCS3IOSRendererBackend {
    RPCS3IOSRendererVulkan = 0,
    RPCS3IOSRendererMetal = 1
} RPCS3IOSRendererBackend;

typedef enum RPCS3IOSCoreOperation {
    RPCS3IOSCoreOperationBoot = 0,
    RPCS3IOSCoreOperationPause = 1,
    RPCS3IOSCoreOperationResume = 2,
    RPCS3IOSCoreOperationRestart = 3,
    RPCS3IOSCoreOperationStop = 4,
    RPCS3IOSCoreOperationBootVSH = 5,
    RPCS3IOSCoreOperationInsertDisc = 6,
    RPCS3IOSCoreOperationEjectDisc = 7,
    RPCS3IOSCoreOperationInstallPackage = 8,
    RPCS3IOSCoreOperationInstallFirmware = 9,
    RPCS3IOSCoreOperationAddGame = 10
} RPCS3IOSCoreOperation;

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
    int upstream_runtime_linked;
    int host_callbacks_initialized;
    RPCS3IOSRendererBackend selected_renderer;
    const char *upstream_revision;
    const char *build_classification;
    const char *data_path;
    const char *last_boot_sha256;
    const char *message;
} RPCS3IOSCoreDiagnostics;

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void);
int rpcs3_ios_core_initialize(const char *data_path);

/* Selects the renderer used when RPCS3 creates its next GSRender instance. */
int rpcs3_ios_core_set_renderer(RPCS3IOSRendererBackend renderer);
RPCS3IOSRendererBackend rpcs3_ios_core_get_renderer(void);

/* Boot a game directory, ISO, SELF, ELF, EBOOT.BIN, or VSH path through Emu.System. */
int rpcs3_ios_core_boot_path(const char *path);
/* Compatibility alias retained for existing callers. */
int rpcs3_ios_core_boot_elf(const char *elf_path);

int rpcs3_ios_core_pause(void);
int rpcs3_ios_core_resume(void);
int rpcs3_ios_core_restart(void);
void rpcs3_ios_core_stop(void);
int rpcs3_ios_core_boot_vsh(void);
int rpcs3_ios_core_insert_disc(const char *path);
int rpcs3_ios_core_eject_disc(void);
int rpcs3_ios_core_install_package(const char *path);
int rpcs3_ios_core_install_firmware(const char *path);
int rpcs3_ios_core_add_game(const char *path);
int rpcs3_ios_core_operation_available(RPCS3IOSCoreOperation operation);

#ifdef __cplusplus
}
#endif
