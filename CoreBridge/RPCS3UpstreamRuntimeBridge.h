#pragma once

#ifdef __cplusplus
extern "C" {
#endif

typedef enum RPCS3IOSUpstreamState {
    RPCS3IOSUpstreamStateUninitialized = 0,
    RPCS3IOSUpstreamStateReady = 1,
    RPCS3IOSUpstreamStateRunning = 2,
    RPCS3IOSUpstreamStatePaused = 3,
    RPCS3IOSUpstreamStateStopped = 4,
    RPCS3IOSUpstreamStateFailed = 5
} RPCS3IOSUpstreamState;

// Attaches a runtime-owned CAMetalLayer to the native iOS UIView represented by
// a Qt QWidget::winId(). The view must remain alive while emulation is active.
int rpcs3_ios_upstream_set_render_view(void* native_view);
void rpcs3_ios_upstream_clear_render_view(void);
int rpcs3_ios_upstream_render_view_ready(void);

// Initializes the real upstream Emulator singleton using static PPU/SPU
// interpreters and the supplied sandbox data root.
int rpcs3_ios_upstream_initialize(const char* data_root);

// Installs a PS3 PKG through upstream package_reader::extract_data(). Returns 1
// only when RPCS3 reports a complete successful extraction into dev_hdd0/game.
int rpcs3_ios_upstream_install_pkg(const char* pkg_path);
const char* rpcs3_ios_upstream_last_installed_boot_path(void);

// Boots a folder, EBOOT.BIN, SELF/ELF, or installed dev_hdd0/game title through
// upstream Emulator::BootGame. Returns the upstream game_boot_result value;
// game_boot_result::no_errors is zero.
int rpcs3_ios_upstream_boot_game(const char* path);

int rpcs3_ios_upstream_pause(void);
int rpcs3_ios_upstream_resume(void);
int rpcs3_ios_upstream_stop(void);
RPCS3IOSUpstreamState rpcs3_ios_upstream_state(void);
int rpcs3_ios_upstream_last_boot_result(void);
const char* rpcs3_ios_upstream_last_message(void);

// Kept for the CI link probe and compatibility with the previous bridge name.
int rpcs3_ios_upstream_runtime_link_probe(const char* data_root);

#ifdef __cplusplus
}
#endif
