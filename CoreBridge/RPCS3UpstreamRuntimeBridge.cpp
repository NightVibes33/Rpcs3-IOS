#include "Emu/System.h"
#include "Emu/system_config.h"
#include "Utilities/File.h"

#include <filesystem>
#include <mutex>
#include <string>

namespace
{
std::mutex g_probe_mutex;
bool g_probe_initialized = false;
std::string g_probe_data_root;

void configure_interpreter_lane()
{
    // This bridge intentionally starts with RPCS3's interpreter and Null RSX
    // lane. Metal rendering is connected after real guest initialization is
    // proven; LLVM/JIT and desktop renderers must never be silently selected.
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
    callbacks.on_run = [](bool) {};
    callbacks.on_pause = []() {};
    callbacks.on_resume = []() {};
    callbacks.on_stop = []() {};
    callbacks.on_ready = []() {};
    callbacks.on_missing_fw = []() {};
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
}

extern "C" int rpcs3_ios_upstream_runtime_link_probe(const char* data_root)
{
    std::lock_guard lock(g_probe_mutex);
    if (g_probe_initialized)
    {
        return 1;
    }

    g_probe_data_root = data_root && *data_root ? data_root : fs::get_config_dir();
    std::error_code error;
    std::filesystem::create_directories(g_probe_data_root, error);
    if (error)
    {
        return 0;
    }

    configure_interpreter_lane();
    install_minimal_callbacks();
    Emu.SetHasGui(false);
    Emu.SetUsr("00000001");
    Emu.Init();
    g_probe_initialized = true;
    return 1;
}
