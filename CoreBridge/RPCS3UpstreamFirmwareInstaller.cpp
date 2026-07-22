#include "RPCS3UpstreamRuntimeBridge.h"

#include "Crypto/unself.h"
#include "Emu/System.h"
#include "Emu/VFS.h"
#include "Emu/vfs_config.h"
#include "Loader/PUP.h"
#include "Loader/TAR.h"
#include "Utilities/File.h"
#include "util/serialization_ext.hpp"
#include "util/sysinfo.hpp"

#include <algorithm>
#include <filesystem>
#include <mutex>
#include <string>
#include <vector>

namespace
{
std::mutex g_firmware_mutex;
std::string g_firmware_message = "PS3 firmware has not been installed.";
std::string g_firmware_version;

void set_firmware_failure(std::string message)
{
    g_firmware_message = std::move(message);
}

std::string dev_flash_root()
{
    return g_cfg_vfs.get_dev_flash();
}

bool firmware_ready_unlocked()
{
    const std::string root = dev_flash_root();
    return !root.empty() && fs::is_file(root + "vsh/module/vsh.self");
}

bool reinitialize_after_firmware_mount()
{
    try
    {
        // This mirrors upstream main_window::HandlePupInstallation. Emu.Init()
        // rebuilds the VFS mounts after the temporary /dev_flash extraction mount.
        Emu.Init();
        return true;
    }
    catch (...)
    {
        return false;
    }
}

bool fail_after_mount(std::string message)
{
    reinitialize_after_firmware_mount();
    set_firmware_failure(std::move(message));
    return false;
}
} // namespace

extern "C" int rpcs3_ios_upstream_install_firmware(const char* pup_path)
{
    std::lock_guard lock(g_firmware_mutex);
    g_firmware_version.clear();

    if (!pup_path || !*pup_path)
    {
        set_firmware_failure("No PS3UPDAT.PUP path was supplied.");
        return 0;
    }

    std::error_code filesystem_error;
    if (!std::filesystem::is_regular_file(pup_path, filesystem_error) || filesystem_error)
    {
        set_firmware_failure("The selected PS3UPDAT.PUP is not a readable regular file.");
        return 0;
    }

    try
    {
        if (!Emu.IsStopped())
        {
            Emu.Kill(false);
        }

        fs::file pup_file(pup_path);
        if (!pup_file)
        {
            set_firmware_failure("RPCS3 could not open the selected PS3UPDAT.PUP.");
            return 0;
        }

        pup_object pup(std::move(pup_file));
        switch (static_cast<pup_error>(pup))
        {
        case pup_error::ok:
            break;
        case pup_error::header_read:
            set_firmware_failure("The selected PS3UPDAT.PUP is empty.");
            return 0;
        case pup_error::header_magic:
            set_firmware_failure("The selected file is not a valid PS3 PUP firmware file.");
            return 0;
        case pup_error::expected_size:
            set_firmware_failure("The selected PS3UPDAT.PUP is incomplete. Download it again from Sony.");
            return 0;
        case pup_error::hash_mismatch:
            set_firmware_failure("The PS3UPDAT.PUP hash validation failed; its contents are corrupted.");
            return 0;
        case pup_error::header_file_count:
        case pup_error::file_entries:
        case pup_error::stream:
        default:
            set_firmware_failure(pup.get_formatted_error().empty()
                ? "RPCS3 rejected the PS3UPDAT.PUP structure as corrupted."
                : "RPCS3 rejected the PS3UPDAT.PUP: " + pup.get_formatted_error());
            return 0;
        }

        fs::file update_files_file = pup.get_file(0x300);
        const usz update_files_size = update_files_file ? update_files_file.size() : 0;
        if (!update_files_size)
        {
            set_firmware_failure("RPCS3 could not find the firmware installation package database in the PUP.");
            return 0;
        }

        fs::device_stat device_stat{};
        const std::string flash_root = dev_flash_root();
        if (flash_root.empty() || !fs::statfs(flash_root, device_stat))
        {
            set_firmware_failure("RPCS3 could not determine free space for the dev_flash installation.");
            return 0;
        }
        if (device_stat.avail_free < update_files_size)
        {
            set_firmware_failure("There is not enough free space to install PS3 firmware into dev_flash.");
            return 0;
        }

        tar_object update_files(update_files_file);
        std::vector<std::string> update_filenames = update_files.get_filenames();
        update_filenames.erase(
            std::remove_if(update_filenames.begin(), update_filenames.end(), [](const std::string& name)
            {
                return name.find("dev_flash_") == std::string::npos;
            }),
            update_filenames.end());

        if (update_filenames.empty())
        {
            set_firmware_failure("The PUP does not contain any dev_flash_* firmware packages.");
            return 0;
        }

        std::string pup_version;
        if (fs::file version_file = pup.get_file(0x100))
        {
            pup_version = version_file.to_string();
        }
        if (const std::size_t newline = pup_version.find('\n'); newline != std::string::npos)
        {
            pup_version.erase(newline);
        }
        if (pup_version.empty())
        {
            set_firmware_failure("RPCS3 could not read the firmware version from the PUP.");
            return 0;
        }

        // Upstream firmware TAR entries contain /dev_flash paths. Mount the same
        // virtual destination used by desktop RPCS3 before extracting them.
        if (!vfs::mount("/dev_flash", flash_root))
        {
            set_firmware_failure("RPCS3 could not mount the dev_flash destination for firmware installation.");
            return 0;
        }

        for (const std::string& update_filename : update_filenames)
        {
            std::unique_ptr<utils::serial> update_stream = update_files.get_file(update_filename);
            if (!update_stream)
            {
                return fail_after_mount("RPCS3 could not read firmware package " + update_filename + ".") ? 1 : 0;
            }

            if (update_stream->m_file_handler)
            {
                update_stream->m_file_handler->handle_file_op(
                    *update_stream, 0, update_stream->get_size(umax), nullptr);
            }

            fs::file encrypted_package = fs::make_stream(std::move(update_stream->data));
            if (!encrypted_package)
            {
                return fail_after_mount("RPCS3 could not open nested firmware package " + update_filename + ".") ? 1 : 0;
            }

            SCEDecrypter decrypter(encrypted_package);
            if (!decrypter.LoadHeaders() ||
                !decrypter.LoadMetadata(SCEPKG_ERK, SCEPKG_RIV) ||
                !decrypter.DecryptData())
            {
                return fail_after_mount("RPCS3 failed to decrypt firmware package " + update_filename + ".") ? 1 : 0;
            }

            std::vector<fs::file> decrypted_files = decrypter.MakeFile();
            if (decrypted_files.size() < 3 || !decrypted_files[2])
            {
                return fail_after_mount("RPCS3 could not decompress firmware package " + update_filename + ".") ? 1 : 0;
            }

            tar_object dev_flash_tar(decrypted_files[2]);
            if (!dev_flash_tar.extract())
            {
                return fail_after_mount("RPCS3 could not extract firmware package " + update_filename + " into dev_flash.") ? 1 : 0;
            }
        }

        update_files_file.close();
        if (!reinitialize_after_firmware_mount())
        {
            set_firmware_failure("Firmware files were extracted, but RPCS3 failed to rebuild its VFS afterwards.");
            return 0;
        }

        if (!firmware_ready_unlocked())
        {
            set_firmware_failure("Firmware extraction finished, but dev_flash/vsh/module/vsh.self is missing.");
            return 0;
        }

        g_firmware_version = utils::get_firmware_version();
        if (g_firmware_version.empty())
        {
            g_firmware_version = pup_version;
        }
        g_firmware_message = "RPCS3 installed PS3 firmware " + g_firmware_version +
            " and validated dev_flash/vsh/module/vsh.self.";
        return 1;
    }
    catch (const std::exception& error)
    {
        set_firmware_failure(std::string("RPCS3 firmware installation failed: ") + error.what());
        return 0;
    }
    catch (...)
    {
        set_firmware_failure("RPCS3 firmware installation failed with an unknown exception.");
        return 0;
    }
}

extern "C" int rpcs3_ios_upstream_firmware_ready(void)
{
    std::lock_guard lock(g_firmware_mutex);
    return firmware_ready_unlocked() ? 1 : 0;
}

extern "C" const char* rpcs3_ios_upstream_firmware_version(void)
{
    thread_local std::string copy;
    std::lock_guard lock(g_firmware_mutex);
    if (firmware_ready_unlocked())
    {
        g_firmware_version = utils::get_firmware_version();
    }
    else
    {
        g_firmware_version.clear();
    }
    copy = g_firmware_version;
    return copy.c_str();
}

extern "C" const char* rpcs3_ios_upstream_firmware_last_message(void)
{
    thread_local std::string copy;
    std::lock_guard lock(g_firmware_mutex);
    copy = g_firmware_message;
    return copy.c_str();
}
