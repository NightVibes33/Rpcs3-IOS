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

typedef struct RPCS3IOSCoreDiagnostics {
    RPCS3IOSCoreState state;
    int platform_initialized;
    int ppu_interpreter_available;
    int spu_interpreter_available;
    int jit_available;
    int renderer_available;
    const char *data_path;
    const char *message;
} RPCS3IOSCoreDiagnostics;

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void);
int rpcs3_ios_core_initialize(const char *data_path);
int rpcs3_ios_core_boot_elf(const char *elf_path);
void rpcs3_ios_core_stop(void);

#ifdef __cplusplus
}
#endif
