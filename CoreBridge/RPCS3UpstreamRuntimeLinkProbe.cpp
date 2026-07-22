#include "RPCS3UpstreamRuntimeBridge.h"

int main()
{
    // This executable is cross-linked for arm64 iOS but is not executed in CI.
    // Referencing every vertical-slice entry forces the linker to resolve the
    // real Emulator singleton, VKGSRender/MoltenVK CAMetalLayer presentation,
    // package_reader installation, BootGame, pause/resume/stop, interpreter
    // code, and all transitive runtime dependencies used by the first PKG.
    (void)rpcs3_ios_upstream_set_render_view(nullptr);
    (void)rpcs3_ios_upstream_render_view_ready();
    rpcs3_ios_upstream_clear_render_view();

    if (!rpcs3_ios_upstream_runtime_link_probe(nullptr))
    {
        return 1;
    }

    const int install_result = rpcs3_ios_upstream_install_pkg("/nonexistent-rpcs3-ios-link-probe.pkg");
    const char* installed_path = rpcs3_ios_upstream_last_installed_boot_path();
    const int boot_result = rpcs3_ios_upstream_boot_game("/nonexistent-rpcs3-ios-link-probe");
    const int last_result = rpcs3_ios_upstream_last_boot_result();
    const RPCS3IOSUpstreamState state = rpcs3_ios_upstream_state();
    const char* message = rpcs3_ios_upstream_last_message();

    // These calls are deliberately present for link coverage. The executable
    // never runs in CI, so their runtime return values are irrelevant.
    (void)install_result;
    (void)installed_path;
    (void)boot_result;
    (void)last_result;
    (void)state;
    (void)message;
    (void)rpcs3_ios_upstream_pause();
    (void)rpcs3_ios_upstream_resume();
    (void)rpcs3_ios_upstream_stop();
    return 0;
}
