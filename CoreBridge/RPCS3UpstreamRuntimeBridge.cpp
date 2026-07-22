#include "RPCS3UpstreamRuntimeBridge.h"

#include "Emu/System.h"
#include "Emu/system_config.h"

#include <atomic>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <mutex>
#include <string>

namespace
{
std::mutex g_runtime_mutex;
std::atomic<RPCS3IOSUpstreamState> g_runtime_state{RPCS3IOSUpstreamStateUninitialized};
bool g_runtime_initialized = false;
std::string g_runtime_data_root;
std::string g_last_message = "The upstream RPCS3 runtime is not initialized.";
int g_last_boot_result = static_cast<int>(game_boot_result::nothing_to_boot);

void set_state(RPCS3IOSUpstreamState state, std::string message)
{
    g_runtime_state.store(state, std::memory_order_release);
    g_last_message = std::move(message);
}

void configure_interpreter_lane()
{
    // First-playable-PKG lane: use RPCS3's real interpreters while JIT remains
    // unavailable to an ordinarily signed iOS application. Null RSX/audio keep
    // execution bring-up independent from the later Metal and AudioUnit work.
    g_cfg.core.ppu_decoder.set(ppu_decoder_type::interpreter);
    g_cfg.core.spu_decoder.set(spu_decoder_type::interpreter_precise);
    g_cfg.video.renderer.set(video_renderer::null);
    g_cfg.audio.renderer.set(audio_renderer::null);
    g_cfg.io.keyboard.set(keyboard_handler::null);
    g_cfg.io.mouse.set(mouse_handler::null);
    g_cfg.io.camera.set(camera_handler::null);
    g_cfg.audio.music.set(music_handler::null);
}

void install_minimal_callbacks()
{
    EmuCallbacks callbacks{};
    callbacks.call_from_main_thread = [](std::function<void()> function, atomic_t<u32>* wake_up)
    {
        // The initial bridge is invoked from the host UI thread. A dispatch hook
        // replaces this inline fallback when the runtime is embedded in the IPA.
        if (function)
        {
            function();
        }
        if (wake_up)
        {
            *wake_up = true;
            wake_up->notify_one();
        }
    };
    callbacks.on_run = [](bool)
    {
        g_runtime_state.store(RPCS3IOSUpstreamStateRunning, std::memory_order_release);
    };
    callbacks.on_pause = []()
    {
        g_runtime_state.store(RPCS3IOSUpstreamStatePaused, std::memory_order_release);
    };
    callbacks.on_resume = []()
    {
        g_runtime_state.store(RPCS3IOSUpstreamStateRunning, std::memory_order_release);
    };
    callbacks.on_stop = []()
    {
        g_runtime_state.store(RPCS3IOSUpstreamStateStopped, std::memory_order_release);
    };
    callbacks.on_ready = []()
    {
        g_runtime_state.store(RPCS3IOSUpstreamStateReady, std::memory_order_release);
    };
    callbacks.on_missing_fw = []()
    {
        g_runtime_state.store(RPCS3IOSUpstreamStateFailed, std::memory_order_release);
    };
    callbacks.on_emulation_stop_no_response = [](std::shared_ptr<atomic_t<bool>>, int) {};
    callbacks.on_save_state_progress = [](std::shared_ptr<atomic_t<bool>>, stx::shared_ptr<utils::serial>, stx::atomic_ptr<std::string>*, std::shared_ptr<void>) {};
    callbacks.enable_disc_eject = [](bool) {};
    callbacks.enable_disc_insert = [](bool) {};
    callbacks.try_to_quit = [](bool, std::function<void()> on_exit)
    {
        if (on_exit)
        {
            on_exit();
        }
        return true;
    };
    callbacks.handle_taskbar_progress = [](s32, s32) {};
    callbacks.init_kb_handler = []() {};
    callbacks.init_mouse_handler = []() {};
    callbacks.init_pad_handler = [](std::string_view) {};
    callbacks.update_emu_settings = []() {};
    callbacks.save_emu_settings = []() {};
    callbacks.close_gs_frame = []() {};
    callbacks.get_gs_frame = []() -> std::unique_ptr<GSFrameBase> { return {}; };
    callbacks.get_camera_handler = []() -> std::shared_ptr<camera_handler_base> { return {}; };
    callbacks.get_music_handler = []() -> std::shared_ptr<music_handler_base> { return {}; };
    callbacks.init_gs_render = [](utils::serial*) {};
    callbacks.get_audio = []() -> std::shared_ptr<AudioBackend> { return {}; };
    callbacks.get_audio_enumerator = [](u64) -> std::shared_ptr<audio_device_enumerator> { return {}; };
    callbacks.get_msg_dialog = []() -> std::shared_ptr<MsgDialogBase> { return {}; };
    callbacks.get_osk_dialog = []() -> std::shared_ptr<OskDialogBase> { return {}; };
    callbacks.get_save_dialog = []() -> std::unique_ptr<SaveDialogBase> { return {}; };
    callbacks.get_sendmessage_dialog = []() -> std::shared_ptr<SendMessageDialogBase> { return {}; };
    callbacks.get_recvmessage_dialog = []() -> std::shared_ptr<RecvMessageDialogBase> { return {}; };
    callbacks.get_trophy_notification_dialog = []() -> std::unique_ptr<TrophyNotificationBase> { return {}; };
    callbacks.get_localized_string = [](localized_string_id, const char*) -> std::string { return {}; };
    callbacks.get_localized_u32string = [](localized_string_id, const char*) -> std::u32string { return {}; };
    callbacks.get_localized_setting = [](const cfg::_base*, u32) -> std::string { return {}; };
    callbacks.get_photo_path = [](std::string_view) -> std::string { return {}; };
    callbacks.play_sound = [](const std::string&, std::optional<f32>) {};
    callbacks.get_image_info = [](const std::string&, std::string&, s32&, s32&, s32&) { return false; };
    callbacks.get_scaled_image = [](const std::string&, s32, s32, s32&, s32&, u8*, bool) { return false; };
    callbacks.get_font_dirs = []() -> std::vector<std::string> { return {}; };
    callbacks.on_install_pkgs = [](const std::vector<std::string>&) { return false; };
    callbacks.add_breakpoint = [](u32) {};
    callbacks.display_sleep_control_supported = []() { return false; };
    callbacks.enable_display_sleep = [](bool) {};
    callbacks.check_microphone_permissions = []() {};
    callbacks.make_video_source = []() -> std::unique_ptr<video_source> { return {}; };
    callbacks.enable_gamemode = [](bool) {};
    Emu.SetCallbacks(std::move(callbacks));
}

std::string resolve_data_root(const char* data_root)
{
    if (data_root && *data_root)
    {
        return std::filesystem::path(data_root).lexically_normal().string();
    }

    std::error_code error;
    const std::filesystem::path temporary = std::filesystem::temp_directory_path(error);
    if (!error)
    {
        return (temporary / "rpcs3-ios-runtime").string();
    }
    return "./rpcs3-ios-runtime";
}
} // namespace

extern "C" int rpcs3_ios_upstream_initialize(const char* data_root)
{
    std::lock_guard lock(g_runtime_mutex);
    if (g_runtime_initialized)
    {
        return 1;
    }

    try
    {
        g_runtime_data_root = resolve_data_root(data_root);
        std::error_code error;
        std::filesystem::create_directories(g_runtime_data_root, error);
        if (error)
        {
            set_state(RPCS3IOSUpstreamStateFailed, "Unable to create the RPCS3 data root: " + error.message());
            return 0;
        }

        // The iOS upstream overlay makes RPCS3_CONFIG_DIR authoritative before
        // fs::get_config_dir() caches its first value.
        if (::setenv("RPCS3_CONFIG_DIR", g_runtime_data_root.c_str(), 1) != 0)
        {
            set_state(RPCS3IOSUpstreamStateFailed, "Unable to set RPCS3_CONFIG_DIR for the upstream runtime.");
            return 0;
        }

        configure_interpreter_lane();
        install_minimal_callbacks();
        Emu.SetHasGui(false);
        Emu.SetUsr("00000001");
        Emu.Init();

        g_runtime_initialized = true;
        g_last_boot_result = static_cast<int>(game_boot_result::nothing_to_boot);
        set_state(RPCS3IOSUpstreamStateReady, "Real upstream Emu.Init completed in interpreter/Null-RSX mode.");
        return 1;
    }
    catch (const std::exception& error)
    {
        set_state(RPCS3IOSUpstreamStateFailed, std::string("Upstream Emu.Init failed: ") + error.what());
        return 0;
    }
    catch (...)
    {
        set_state(RPCS3IOSUpstreamStateFailed, "Upstream Emu.Init failed with an unknown exception.");
        return 0;
    }
}

extern "C" int rpcs3_ios_upstream_boot_game(const char* path)
{
    std::lock_guard lock(g_runtime_mutex);
    if (!g_runtime_initialized)
    {
        g_last_boot_result = static_cast<int>(game_boot_result::generic_error);
        set_state(RPCS3IOSUpstreamStateFailed, "Initialize the real upstream runtime before booting a title.");
        return g_last_boot_result;
    }
    if (!path || !*path)
    {
        g_last_boot_result = static_cast<int>(game_boot_result::nothing_to_boot);
        set_state(RPCS3IOSUpstreamStateFailed, "No RPCS3 boot path was supplied.");
        return g_last_boot_result;
    }

    std::error_code error;
    if (!std::filesystem::exists(path, error) || error)
    {
        g_last_boot_result = static_cast<int>(game_boot_result::invalid_file_or_folder);
        set_state(RPCS3IOSUpstreamStateFailed, "The RPCS3 boot path does not exist inside the app sandbox.");
        return g_last_boot_result;
    }

    try
    {
        Emu.argv.clear();
        Emu.SetForceBoot(true);
        const game_boot_result result = Emu.BootGame(path, "", false, cfg_mode::custom, "");
        g_last_boot_result = static_cast<int>(result);
        if (result == game_boot_result::no_errors)
        {
            if (Emu.IsRunning())
            {
                set_state(RPCS3IOSUpstreamStateRunning, "Upstream Emulator::BootGame accepted and started the title.");
            }
            else if (Emu.IsPausedOrReady())
            {
                set_state(RPCS3IOSUpstreamStateReady, "Upstream Emulator::BootGame accepted the title and reached ready state.");
            }
            else
            {
                set_state(RPCS3IOSUpstreamStateReady, "Upstream Emulator::BootGame accepted the title.");
            }
        }
        else
        {
            set_state(RPCS3IOSUpstreamStateFailed, "Upstream Emulator::BootGame rejected the supplied title.");
        }
        return g_last_boot_result;
    }
    catch (const std::exception& error)
    {
        g_last_boot_result = static_cast<int>(game_boot_result::generic_error);
        set_state(RPCS3IOSUpstreamStateFailed, std::string("Upstream BootGame failed: ") + error.what());
        return g_last_boot_result;
    }
    catch (...)
    {
        g_last_boot_result = static_cast<int>(game_boot_result::generic_error);
        set_state(RPCS3IOSUpstreamStateFailed, "Upstream BootGame failed with an unknown exception.");
        return g_last_boot_result;
    }
}

extern "C" int rpcs3_ios_upstream_pause(void)
{
    std::lock_guard lock(g_runtime_mutex);
    if (!g_runtime_initialized || !Emu.IsRunning())
    {
        return 0;
    }
    if (!Emu.Pause())
    {
        return 0;
    }
    set_state(RPCS3IOSUpstreamStatePaused, "Upstream emulation paused.");
    return 1;
}

extern "C" int rpcs3_ios_upstream_resume(void)
{
    std::lock_guard lock(g_runtime_mutex);
    if (!g_runtime_initialized || !Emu.IsPaused())
    {
        return 0;
    }
    Emu.Resume();
    set_state(RPCS3IOSUpstreamStateRunning, "Upstream emulation resumed.");
    return 1;
}

extern "C" int rpcs3_ios_upstream_stop(void)
{
    std::lock_guard lock(g_runtime_mutex);
    if (!g_runtime_initialized)
    {
        return 0;
    }
    if (!Emu.IsStopped())
    {
        Emu.Kill(false);
    }
    set_state(RPCS3IOSUpstreamStateStopped, "Upstream emulation stopped.");
    return 1;
}

extern "C" RPCS3IOSUpstreamState rpcs3_ios_upstream_state(void)
{
    return g_runtime_state.load(std::memory_order_acquire);
}

extern "C" int rpcs3_ios_upstream_last_boot_result(void)
{
    std::lock_guard lock(g_runtime_mutex);
    return g_last_boot_result;
}

extern "C" const char* rpcs3_ios_upstream_last_message(void)
{
    thread_local std::string copy;
    std::lock_guard lock(g_runtime_mutex);
    copy = g_last_message;
    return copy.c_str();
}

extern "C" int rpcs3_ios_upstream_runtime_link_probe(const char* data_root)
{
    return rpcs3_ios_upstream_initialize(data_root);
}
