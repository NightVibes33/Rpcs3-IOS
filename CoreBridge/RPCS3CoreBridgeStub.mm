#include "RPCS3CoreBridge.h"

static const char *kUnavailable =
    "RPCS3 core is not linked. Run the portability audit and replace this stub only after the interpreter-only static core builds for arm64 iPhoneOS.";

RPCS3IOSCoreDiagnostics rpcs3_ios_core_diagnostics(void)
{
    RPCS3IOSCoreDiagnostics result = {};
    result.state = RPCS3IOSCoreStateUnavailable;
    result.ppu_interpreter_available = 0;
    result.spu_interpreter_available = 0;
    result.jit_available = 0;
    result.renderer_available = 0;
    result.message = kUnavailable;
    return result;
}

int rpcs3_ios_core_initialize(const char *data_path)
{
    (void)data_path;
    return 0;
}

int rpcs3_ios_core_boot_elf(const char *elf_path)
{
    (void)elf_path;
    return 0;
}

void rpcs3_ios_core_stop(void)
{
}
