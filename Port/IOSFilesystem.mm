#include "IOSFilesystem.h"

#import <Foundation/Foundation.h>

#include <cstdlib>
#include <filesystem>

namespace rpcs3::ios
{
namespace
{
std::string utf8(NSString* value)
{
    if (!value)
    {
        return {};
    }

    const char* text = value.fileSystemRepresentation;
    return text ? std::string(text) : std::string{};
}

NSString* normalized_path(NSString* value)
{
    if (!value.length)
    {
        return nil;
    }

    return value.stringByStandardizingPath.stringByResolvingSymlinksInPath;
}

bool create_directory(NSFileManager* manager, NSString* path, std::string& error)
{
    NSError* creation_error = nil;
    if ([manager createDirectoryAtPath:path
           withIntermediateDirectories:YES
                            attributes:nil
                                 error:&creation_error])
    {
        return true;
    }

    error = utf8(creation_error.localizedDescription ?: @"Unable to create directory");
    return false;
}

bool create_default_user_file(NSFileManager* manager, NSString* root, std::string& error)
{
    NSString* user_file = [root stringByAppendingPathComponent:@"dev_hdd0/home/00000001/localusername"];
    if ([manager fileExistsAtPath:user_file])
    {
        return true;
    }

    NSError* write_error = nil;
    if ([ @"User" writeToFile:user_file
                   atomically:YES
                     encoding:NSUTF8StringEncoding
                        error:&write_error])
    {
        return true;
    }

    error = utf8(write_error.localizedDescription ?: @"Unable to create the default RPCS3 user file");
    return false;
}

void exclude_from_backup(NSString* path)
{
    NSURL* url = [NSURL fileURLWithPath:path isDirectory:YES];
    NSError* error = nil;
    [url setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:&error];
    (void)error;
}
} // namespace

bool path_is_within_app_container(const char* path) noexcept
{
    @autoreleasepool
    {
        if (!path || !*path)
        {
            return false;
        }

        NSString* candidate = normalized_path([NSString stringWithUTF8String:path]);
        NSString* home = normalized_path(NSHomeDirectory());
        if (!candidate || !home)
        {
            return false;
        }

        if ([candidate isEqualToString:home])
        {
            return true;
        }

        NSString* prefix = [home stringByAppendingString:@"/"];
        return [candidate hasPrefix:prefix];
    }
}

filesystem_layout prepare_filesystem_layout(const char* root_override) noexcept
{
    @autoreleasepool
    {
        filesystem_layout result;
        NSFileManager* manager = NSFileManager.defaultManager;

        NSString* root = nil;
        if (root_override && *root_override)
        {
            if (!path_is_within_app_container(root_override))
            {
                result.error = "Requested RPCS3 root is outside the app container";
                return result;
            }
            root = normalized_path([NSString stringWithUTF8String:root_override]);
        }
        else
        {
            NSURL* support = [manager URLsForDirectory:NSApplicationSupportDirectory
                                             inDomains:NSUserDomainMask].firstObject;
            if (!support)
            {
                result.error = "Application Support directory is unavailable";
                return result;
            }
            root = [support.path stringByAppendingPathComponent:@"RPCS3"];
        }

        NSDictionary<NSString*, NSString*>* roots = @{
            @"root": root,
            @"config": [root stringByAppendingPathComponent:@"config"],
            @"dev_hdd0": [root stringByAppendingPathComponent:@"dev_hdd0"],
            @"dev_hdd1": [root stringByAppendingPathComponent:@"dev_hdd1"],
            @"dev_flash": [root stringByAppendingPathComponent:@"dev_flash"],
            @"dev_flash2": [root stringByAppendingPathComponent:@"dev_flash2"],
            @"dev_flash3": [root stringByAppendingPathComponent:@"dev_flash3"],
            @"dev_bdvd": [root stringByAppendingPathComponent:@"dev_bdvd"],
            @"dev_usb000": [root stringByAppendingPathComponent:@"dev_usb000"],
            @"games": [root stringByAppendingPathComponent:@"games"],
            // Host-only source staging. Installed PKG contents never use a fake
            // /dev_hdd0/pkg directory; package_reader selects the real PS3 path.
            @"packages": [root stringByAppendingPathComponent:@"packages"],
            @"cache": [root stringByAppendingPathComponent:@"cache"],
            @"logs": [root stringByAppendingPathComponent:@"logs"],
            @"imports": [root stringByAppendingPathComponent:@"imports"],
            @"firmware": [root stringByAppendingPathComponent:@"firmware"],
            @"keys": [root stringByAppendingPathComponent:@"keys"],
        };

        for (NSString* key in roots)
        {
            if (!create_directory(manager, roots[key], result.error))
            {
                result.error = "Failed to create RPCS3 root '" + utf8(key) + "': " + result.error;
                return result;
            }
        }

        // Mirror the standard directory tree created by upstream Emulator::Init.
        // Title-specific game folders and PKG entry folders are still generated
        // dynamically by the real upstream loaders and package_reader.
        NSArray<NSString*>* standard_directories = @[
            @"dev_hdd0/game",
            @"dev_hdd0/game/＄locks",
            @"dev_hdd0/game/TEST12345/USRDIR",
            @"dev_hdd0/home",
            @"dev_hdd0/home/00000001",
            @"dev_hdd0/home/00000001/exdata",
            @"dev_hdd0/home/00000001/savedata",
            @"dev_hdd0/home/00000001/trophy",
            @"dev_hdd0/home/00000001/psn_avatar",
            @"dev_hdd0/savedata",
            @"dev_hdd0/savedata/vmc",
            @"dev_hdd0/photo",
            @"dev_hdd0/music",
            @"dev_hdd0/theme",
            @"dev_hdd0/widget",
            @"dev_hdd0/video",
            @"dev_hdd0/drm",
            @"dev_hdd0/vsh",
            @"dev_hdd0/vsh/modules",
            @"dev_hdd0/crash_report",
            @"dev_hdd0/tmp",
            @"dev_hdd0/tmp/vmc",
            @"dev_hdd0/mms",
            @"dev_hdd0/data",
            @"dev_hdd0/vm",
            @"dev_hdd1/caches",
            @"dev_usb000/MUSIC",
            @"dev_usb000/VIDEO",
            @"dev_usb000/PICTURE",
            @"dev_usb000/PS3/EXPORT/PSV",
            @"dev_usb000/PS3/SAVEDATA",
            @"dev_usb000/PS3/THEME",
            @"dev_usb000/PS3/UPDATE",
            @"cache/shaderlog",
            @"cache/spu_progs",
            @"cache/ppu_progs",
            @"config/captures",
            @"config/sounds",
            @"config/patches",
        ];

        for (NSString* relative_path in standard_directories)
        {
            NSString* absolute_path = [root stringByAppendingPathComponent:relative_path];
            if (!create_directory(manager, absolute_path, result.error))
            {
                result.error = "Failed to create RPCS3 path '" + utf8(relative_path) + "': " + result.error;
                return result;
            }
        }

        if (!create_default_user_file(manager, root, result.error))
        {
            return result;
        }

        exclude_from_backup(roots[@"cache"]);
        exclude_from_backup(roots[@"logs"]);
        exclude_from_backup([root stringByAppendingPathComponent:@"dev_hdd1/caches"]);

        result.root = utf8(roots[@"root"]);
        result.config = utf8(roots[@"config"]);
        result.dev_hdd0 = utf8(roots[@"dev_hdd0"]);
        result.dev_hdd1 = utf8(roots[@"dev_hdd1"]);
        result.dev_flash = utf8(roots[@"dev_flash"]);
        result.dev_flash2 = utf8(roots[@"dev_flash2"]);
        result.dev_flash3 = utf8(roots[@"dev_flash3"]);
        result.dev_bdvd = utf8(roots[@"dev_bdvd"]);
        result.dev_usb000 = utf8(roots[@"dev_usb000"]);
        result.games = utf8(roots[@"games"]);
        result.packages = utf8(roots[@"packages"]);
        result.cache = utf8(roots[@"cache"]);
        result.logs = utf8(roots[@"logs"]);
        result.imports = utf8(roots[@"imports"]);
        result.firmware = utf8(roots[@"firmware"]);
        result.keys = utf8(roots[@"keys"]);
        result.ready = true;
        return result;
    }
}
} // namespace rpcs3::ios
