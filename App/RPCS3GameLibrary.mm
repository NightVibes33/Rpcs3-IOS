#import "RPCS3GameLibrary.h"
#include "RPCS3SFO.h"

@implementation RPCS3GameEntry
@end

static NSString *Text(const std::string& value) {
    return value.empty() ? @"" : ([NSString stringWithUTF8String:value.c_str()] ?: @"");
}

static NSURL *FirstExisting(NSURL *root, NSArray<NSString *> *relativePaths) {
    NSFileManager *fm = NSFileManager.defaultManager;
    for (NSString *relative in relativePaths) {
        NSURL *candidate = [root URLByAppendingPathComponent:relative];
        if ([fm fileExistsAtPath:candidate.path]) return candidate;
    }
    return nil;
}

@implementation RPCS3GameLibrary
+ (NSArray<RPCS3GameEntry *> *)scanRoot:(NSString *)rootPath {
    if (!rootPath.length) return @[];
    NSFileManager *fm = NSFileManager.defaultManager;
    NSURL *root = [NSURL fileURLWithPath:rootPath isDirectory:YES];
    NSDirectoryEnumerator<NSURL *> *enumerator = [fm enumeratorAtURL:root
                                         includingPropertiesForKeys:@[NSURLIsDirectoryKey, NSURLNameKey]
                                                            options:NSDirectoryEnumerationSkipsHiddenFiles
                                                       errorHandler:^BOOL(NSURL *url, NSError *error) {
        (void)url; (void)error; return YES;
    }];
    NSMutableArray<RPCS3GameEntry *> *entries = [NSMutableArray array];
    NSMutableSet<NSString *> *seenRoots = [NSMutableSet set];

    for (NSURL *url in enumerator) {
        if (![url.lastPathComponent caseInsensitiveCompare:@"PARAM.SFO"] == NSOrderedSame) continue;
        NSString *parentName = url.URLByDeletingLastPathComponent.lastPathComponent;
        if (![parentName caseInsensitiveCompare:@"PS3_GAME"] == NSOrderedSame &&
            ![parentName caseInsensitiveCompare:@"C00"] == NSOrderedSame &&
            ![parentName caseInsensitiveCompare:@"USRDIR"] == NSOrderedSame) {
            // Installed titles commonly keep PARAM.SFO at the title root; accept those too.
        }
        NSURL *gameRoot = url.URLByDeletingLastPathComponent;
        if ([parentName caseInsensitiveCompare:@"PS3_GAME"] == NSOrderedSame) {
            gameRoot = gameRoot.URLByDeletingLastPathComponent;
        }
        if ([seenRoots containsObject:gameRoot.path]) continue;

        rpcs3::ios::sfo_metadata metadata = rpcs3::ios::read_param_sfo(url.path.fileSystemRepresentation);
        if (!metadata.valid) continue;

        RPCS3GameEntry *entry = [RPCS3GameEntry new];
        entry.title = Text(metadata.title).length ? Text(metadata.title) : gameRoot.lastPathComponent;
        entry.titleID = Text(metadata.title_id);
        entry.category = Text(metadata.category);
        entry.version = Text(metadata.app_version).length ? Text(metadata.app_version) : Text(metadata.version);
        entry.rootURL = gameRoot;
        NSURL *contentRoot = url.URLByDeletingLastPathComponent;
        entry.iconURL = FirstExisting(contentRoot, @[@"ICON0.PNG", @"ICON0.png"]);
        entry.bootURL = FirstExisting(contentRoot, @[@"USRDIR/EBOOT.BIN", @"EBOOT.BIN", @"USRDIR/BOOT.BIN"]);
        [entries addObject:entry];
        [seenRoots addObject:gameRoot.path];
    }

    // Keep standalone imports visible until folder/package installation is complete.
    NSArray<NSURL *> *imports = [fm contentsOfDirectoryAtURL:[root URLByAppendingPathComponent:@"imports"]
                                  includingPropertiesForKeys:nil
                                                     options:NSDirectoryEnumerationSkipsHiddenFiles
                                                       error:nil] ?: @[];
    for (NSURL *url in imports) {
        NSNumber *isDirectory = nil;
        [url getResourceValue:&isDirectory forKey:NSURLIsDirectoryKey error:nil];
        if (isDirectory.boolValue) continue;
        RPCS3GameEntry *entry = [RPCS3GameEntry new];
        entry.title = url.lastPathComponent.stringByDeletingPathExtension;
        entry.titleID = @"";
        entry.category = url.pathExtension.uppercaseString ?: @"BOOT";
        entry.version = @"";
        entry.rootURL = url.URLByDeletingLastPathComponent;
        entry.bootURL = url;
        [entries addObject:entry];
    }

    [entries sortUsingComparator:^NSComparisonResult(RPCS3GameEntry *a, RPCS3GameEntry *b) {
        return [a.title localizedCaseInsensitiveCompare:b.title];
    }];
    return entries;
}
@end
