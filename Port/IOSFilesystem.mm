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

        NSDictionary<NSString*, NSString*>* directories = @{
            @"root": root,
            @"config": [root stringByAppendingPathComponent:@"config"],
            @"dev_hdd0": [root stringByAppendingPathComponent:@"dev_hdd0"],
            @"dev_hdd1": [root stringByAppendingPathComponent:@"dev_hdd1"],
            @"dev_flash": [root stringByAppendingPathComponent:@"dev_flash"],
            @"cache": [root stringByAppendingPathComponent:@"cache"],
            @"logs": [root stringByAppendingPathComponent:@"logs"],
            @"imports": [root stringByAppendingPathComponent:@"imports"],
        };

        for (NSString* key in directories)
        {
            if (!create_directory(manager, directories[key], result.error))
            {
                return result;
            }
        }

        exclude_from_backup(directories[@"cache"]);
        exclude_from_backup(directories[@"logs"]);

        result.root = utf8(directories[@"root"]);
        result.config = utf8(directories[@"config"]);
        result.dev_hdd0 = utf8(directories[@"dev_hdd0"]);
        result.dev_hdd1 = utf8(directories[@"dev_hdd1"]);
        result.dev_flash = utf8(directories[@"dev_flash"]);
        result.cache = utf8(directories[@"cache"]);
        result.logs = utf8(directories[@"logs"]);
        result.imports = utf8(directories[@"imports"]);
        result.ready = true;
        return result;
    }
}
} // namespace rpcs3::ios
