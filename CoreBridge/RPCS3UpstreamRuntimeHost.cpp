#include "RPCS3UpstreamRuntimeHost.h"
#include "IOSFilesystem.h"
#include "RPCS3IOSGSFrame.h"
#include "RPCS3MetalGSRender.h"

#include "Emu/System.h"
#include "Emu/IdManager.h"
#include "Emu/VFS.h"
#include "Emu/vfs_config.h"
#include "Emu/system_config.h"
#include "Emu/system_utils.hpp"
#include "Emu/Audio/Null/NullAudioBackend.h"
#include "Emu/Audio/Null/null_enumerator.h"
#include "Emu/Io/Null/NullKeyboardHandler.h"
#include "Emu/Io/Null/NullMouseHandler.h"
#include "Emu/Io/Null/null_camera_handler.h"
#include "Emu/Io/Null/null_music_handler.h"
#if defined(HAVE_VULKAN)
#include "Emu/RSX/VK/VKGSRender.h"
#endif
#include "Emu/Cell/Modules/cellMsgDialog.h"
#include "Emu/Cell/Modules/cellOskDialog.h"
#include "Emu/Cell/Modules/cellSaveData.h"
#include "Emu/Cell/Modules/sceNpTrophy.h"
#include "Input/pad_thread.h"
#include "Loader/PUP.h"
#include "Loader/TAR.h"
#include "Crypto/unself.h"
#include "Crypto/key_vault.h"
#include "Utilities/File.h"
#include "util/video_source.h"

#include <QCoreApplication>
#include <QFileInfo>
#include <QMetaObject>
#include <QStandardPaths>
#include <QThread>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <optional>
#include <stdexcept>
#include <string>
#include <vector>

namespace rpcs3::ios::upstream
{
namespace
{
filesystem_layout g_layout;
renderer_backend g_renderer = renderer_backend::vulkan;

renderer_backend requested_renderer()
{
    const char* value = std::getenv("RPCS3_IOS_RENDERER");
    if (!value || !*value)
        return renderer_backend::vulkan;

    std::string normalized(value);
    std::transform(normalized.begin(), normalized.end(), normalized.begin(), [](unsigned char character)
    {
        return static_cast<char>(std::tolower(character));
    });
    return normalized == "metal" ? renderer_backend::metal : renderer_backend::vulkan;
}

const char* renderer_name(renderer_backend renderer)
{
    return renderer == renderer_backend::metal ? "Metal" : "Vulkan (MoltenVK)";
}

void wake(atomic_t<u32>* value)
{
    if (!value)
        return;
    *value = true;
    value->notify_one();
}

void call_on_qt_thread(std::function<void()> function, atomic_t<u32>* wake_up)
{
    QCoreApplication* application = QCoreApplication::instance();
    if (!application || QThread::currentThread() == application->thread())
    {
        if (function)
            function();
        wake(wake_up);
        return;
    }

    QMetaObject::invokeMethod(application,
        [function = std::move(function), wake_up]() mutable
        {
            if (function)
                function();
            wake(wake_up);
        },
        Qt::QueuedConnection);
}

EmuCallbacks create_ios_callbacks()
{
    EmuCallbacks callbacks{};

    callbacks.update_emu_settings = []() {};
    callbacks.save_emu_settings = []() {};

    callbacks.init_kb_handler = []()
    {
        ensure(g_fxo->init<KeyboardHandlerBase, NullKeyboardHandler>(Emu.DeserialManager()));
    };

    callbacks.init_mouse_handler = []()
    {
        ensure(g_fxo->init<MouseHandlerBase, NullMouseHandler>(Emu.DeserialManager()));
    };

    callbacks.init_pad_handler = [](std::string_view title_id)
    {
        void* thread = QCoreApplication::instance()
            ? static_cast<void*>(QCoreApplication::instance()->thread())
            : nullptr;
        ensure(g_fxo->init<named_thread<pad_thread>>(thread, nullptr, title_id));
    };

    callbacks.get_audio = []() -> std::shared_ptr<AudioBackend>
    {
        return std::make_shared<NullAudioBackend>();
    };
    callbacks.get_audio_enumerator = [](u64) -> std::shared_ptr<audio_device_enumerator>
    {
        return std::make_shared<null_enumerator>();
    };

    callbacks.init_gs_render = [](utils::serial* archive)
    {
        if (g_renderer == renderer_backend::metal)
        {
            g_fxo->init<rsx::thread, named_thread<rpcs3::ios::render::metal_gs_render>>(archive);
            return;
        }
#if defined(HAVE_VULKAN)
        g_fxo->init<rsx::thread, named_thread<VKGSRender>>(archive);
#else
        throw std::runtime_error("Vulkan was selected, but VKGSRender was not compiled into the iOS runtime.");
#endif
    };
    callbacks.close_gs_frame = []() {};
    callbacks.get_gs_frame = []() -> std::unique_ptr<GSFrameBase>
    {
        return std::make_unique<rpcs3::ios::render::ios_gs_frame>();
    };

    callbacks.get_camera_handler = []() -> std::shared_ptr<camera_handler_base>
    {
        return std::make_shared<null_camera_handler>();
    };
    callbacks.get_music_handler = []() -> std::shared_ptr<music_handler_base>
    {
        return std::make_shared<null_music_handler>();
    };

    callbacks.get_msg_dialog = []() -> std::shared_ptr<MsgDialogBase> { return {}; };
    callbacks.get_osk_dialog = []() -> std::shared_ptr<OskDialogBase> { return {}; };
    callbacks.get_save_dialog = []() -> std::unique_ptr<SaveDialogBase> { return {}; };
    callbacks.get_trophy_notification_dialog = []() -> std::unique_ptr<TrophyNotificationBase> { return {}; };
    callbacks.get_sendmessage_dialog = []() -> std::shared_ptr<SendMessageDialogBase> { return {}; };
    callbacks.get_recvmessage_dialog = []() -> std::shared_ptr<RecvMessageDialogBase> { return {}; };

    callbacks.try_to_quit = [](bool force_quit, std::function<void()> on_exit)
    {
        if (!force_quit)
            return false;
        if (on_exit)
            on_exit();
        return true;
    };
    callbacks.call_from_main_thread = [](std::function<void()> function, atomic_t<u32>* wake_up)
    {
        call_on_qt_thread(std::move(function), wake_up);
    };

    callbacks.on_run = [](bool) {};
    callbacks.on_pause = []() {};
    callbacks.on_resume = []() {};
    callbacks.on_stop = []() {};
    callbacks.on_ready = []() {};
    callbacks.on_emulation_stop_no_response = [](std::shared_ptr<atomic_t<bool>> closed, int)
    {
        if (closed)
            *closed = true;
    };
    callbacks.on_save_state_progress = [](std::shared_ptr<atomic_t<bool>>, stx::shared_ptr<utils::serial>, stx::atomic_ptr<std::string>*, std::shared_ptr<void>) {};

    callbacks.enable_disc_eject = [](bool) {};
    callbacks.enable_disc_insert = [](bool) {};
    callbacks.on_missing_fw = []() {};
    callbacks.handle_taskbar_progress = [](s32, s32) {};

    callbacks.get_localized_string = [](localized_string_id, const char* fallback)
    {
        return fallback ? std::string(fallback) : std::string{};
    };
    callbacks.get_localized_u32string = [](localized_string_id, const char* fallback)
    {
        std::u32string result;
        if (fallback)
            while (*fallback)
                result.push_back(static_cast<unsigned char>(*fallback++));
        return result;
    };
    callbacks.get_localized_setting = [](const cfg::_base*, u32)
    {
        return std::string{};
    };

    callbacks.play_sound = [](const std::string&, std::optional<f32>) {};
    callbacks.add_breakpoint = [](u32) {};
    callbacks.display_sleep_control_supported = []() { return false; };
    callbacks.enable_display_sleep = [](bool) {};
    callbacks.check_microphone_permissions = []() {};
    callbacks.make_video_source = []() { return std::unique_ptr<video_source>{}; };

    callbacks.get_image_info = [](const std::string&, std::string& subtype, s32& width, s32& height, s32& orientation)
    {
        subtype.clear();
        width = 0;
        height = 0;
        orientation = 0;
        return false;
    };
    callbacks.get_scaled_image = [](const std::string&, s32, s32, s32& width, s32& height, u8*, bool)
    {
        width = 0;
        height = 0;
        return false;
    };
    callbacks.resolve_path = [](std::string_view path)
    {
        const QString candidate = QString::fromUtf8(path.data(), static_cast<int>(path.size()));
        const QString canonical = QFileInfo(candidate).canonicalFilePath();
        return (canonical.isEmpty() ? QFileInfo(candidate).absoluteFilePath() : canonical).toStdString();
    };
    callbacks.get_font_dirs = []()
    {
        std::vector<std::string> result;
        for (const QString& path : QStandardPaths::standardLocations(QStandardPaths::FontsLocation))
        {
            std::string value = path.toStdString();
            if (!value.ends_with('/'))
                value.push_back('/');
            result.push_back(std::move(value));
        }
        return result;
    };
    callbacks.on_install_pkgs = [](const std::vector<std::string>& packages)
    {
        return std::all_of(packages.begin(), packages.end(), [](const std::string& path)
        {
            return rpcs3::utils::install_pkg(path);
        });
    };
    callbacks.enable_gamemode = [](bool) {};
    callbacks.get_photo_path = [](std::string_view title)
    {
        std::string safe(title);
        std::replace_if(safe.begin(), safe.end(), [](char value)
        {
            return value == '/' || value == ':' || value == '\\';
        }, '_');
        const std::filesystem::path directory = std::filesystem::path(g_layout.dev_hdd0) / "photo";
        std::error_code error;
        std::filesystem::create_directories(directory, error);
        return (directory / (safe + ".png")).string();
    };

    return callbacks;
}

void configure_sandbox_vfs(const filesystem_layout& layout)
{
    const std::string root = layout.root.ends_with('/') ? layout.root : layout.root + '/';
    g_cfg_vfs.emulator_dir.from_string(root);
    g_cfg_vfs.dev_hdd0.from_string(layout.dev_hdd0 + '/');
    g_cfg_vfs.dev_hdd1.from_string(layout.dev_hdd1 + '/');
    g_cfg_vfs.dev_flash.from_string(layout.dev_flash + '/');
    g_cfg_vfs.games_dir.from_string(layout.imports + '/');
    g_cfg_vfs.save();

    setenv("RPCS3_CONFIG_DIR", layout.config.c_str(), 1);
    setenv("RPCS3_CACHE_DIR", layout.cache.c_str(), 1);
}
} // namespace

bool select_renderer(renderer_backend renderer, std::string& message)
{
    if (!Emu.IsStopped())
    {
        message = "Stop emulation before switching the RPCS3 renderer.";
        return false;
    }
#if !defined(HAVE_VULKAN)
    if (renderer == renderer_backend::vulkan)
    {
        message = "Vulkan was requested, but VKGSRender was not compiled into this build.";
        return false;
    }
#endif

    g_renderer = renderer;
    g_cfg.video.renderer.set(renderer == renderer_backend::vulkan
        ? video_renderer::vulkan
        : video_renderer::null);
    setenv("RPCS3_IOS_RENDERER", renderer == renderer_backend::metal ? "metal" : "vulkan", 1);
    message = std::string("RPCS3 will use ") + renderer_name(renderer) + " on the next boot.";
    return true;
}

renderer_backend selected_renderer() noexcept
{
    return g_renderer;
}

runtime_host_status initialize_runtime_host(const filesystem_layout& layout)
{
    runtime_host_status status;
    g_layout = layout;

    try
    {
        configure_sandbox_vfs(layout);
        std::string selection_message;
        if (!select_renderer(requested_renderer(), selection_message))
            throw std::runtime_error(selection_message);

        g_cfg.audio.renderer.set(audio_renderer::null);
        g_cfg.io.keyboard.set(keyboard_handler::null);
        g_cfg.io.mouse.set(mouse_handler::null);
        g_cfg.io.camera.set(camera_handler::null);
        g_cfg.audio.music.set(music_handler::null);

        Emu.SetHasGui(true);
        Emu.SetUsr("00000001");
        Emu.SetCallbacks(create_ios_callbacks());
        Emu.Init();

        status.initialized = true;
        status.callbacks_initialized = true;
        status.ppu_interpreter = true;
        status.spu_interpreter = true;
        status.jit = false;
        status.renderer = true;
        status.selected_renderer = g_renderer;
        if (g_renderer == renderer_backend::vulkan)
        {
            status.message = "RPCS3 Emu.System initialized with PPU/SPU interpreters, iOS sandbox VFS, a UIKit CAMetalLayer GS frame, and upstream VKGSRender through MoltenVK.";
        }
        else
        {
            status.message = "RPCS3 Emu.System initialized with PPU/SPU interpreters, iOS sandbox VFS, and the native Metal GS renderer. Metal device/queue/presentation are active; RSX draw, shader, texture, and synchronization translation remains in progress.";
        }
    }
    catch (const std::exception& error)
    {
        status.selected_renderer = g_renderer;
        status.message = std::string("RPCS3 Emu.System initialization failed while selecting ") + renderer_name(g_renderer) + ": " + error.what();
    }
    catch (...)
    {
        status.selected_renderer = g_renderer;
        status.message = std::string("RPCS3 Emu.System initialization failed with an unknown exception while selecting ") + renderer_name(g_renderer) + ".";
    }

    return status;
}

bool install_firmware(const std::string& pup_path, std::string& message)
{
    fs::file pup_file(pup_path);
    if (!pup_file)
    {
        message = "The selected PS3UPDAT.PUP could not be opened.";
        return false;
    }

    pup_object pup(std::move(pup_file));
    if (static_cast<pup_error>(pup) != pup_error::ok)
    {
        message = pup.get_formatted_error().empty()
            ? "The selected firmware is not a valid PUP file."
            : pup.get_formatted_error();
        return false;
    }

    fs::file update_files_file = pup.get_file(0x300);
    if (!update_files_file)
    {
        message = "The firmware package database is missing from the PUP.";
        return false;
    }

    tar_object update_files(update_files_file);
    std::vector<std::string> names = update_files.get_filenames();
    std::erase_if(names, [](const std::string& name)
    {
        return name.find("dev_flash_") == std::string::npos;
    });
    if (names.empty())
    {
        message = "The PUP contains no dev_flash firmware packages.";
        return false;
    }

    if (!vfs::mount("/dev_flash", g_layout.dev_flash + '/'))
    {
        message = "RPCS3 could not mount the iOS dev_flash directory.";
        return false;
    }

    for (const std::string& name : names)
    {
        auto stream = update_files.get_file(name);
        if (!stream)
        {
            message = "A dev_flash package could not be read from the PUP.";
            return false;
        }
        if (stream->m_file_handler)
            stream->m_file_handler->handle_file_op(*stream, 0, stream->get_size(umax), nullptr);

        fs::file encrypted = fs::make_stream(std::move(stream->data));
        SCEDecrypter decrypter(encrypted);
        if (!decrypter.LoadHeaders() || !decrypter.LoadMetadata(SCEPKG_ERK, SCEPKG_RIV) || !decrypter.DecryptData())
        {
            message = "RPCS3 could not decrypt a dev_flash firmware package.";
            return false;
        }

        auto files = decrypter.MakeFile();
        if (files.size() < 3)
        {
            message = "A decrypted firmware package did not contain a dev_flash archive.";
            return false;
        }

        tar_object archive(files[2]);
        if (!archive.extract())
        {
            message = "RPCS3 could not extract a dev_flash firmware archive.";
            return false;
        }
    }

    Emu.Init();
    message = "RPCS3 installed PS3 firmware into the app's dev_flash tree.";
    return true;
}
} // namespace rpcs3::ios::upstream
