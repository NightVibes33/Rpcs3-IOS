#import "RPCS3DynamicCore.h"
#include "RPCS3IOS.h"

#import <dlfcn.h>
#import <os/log.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>

static NSString * const RPCS3DynamicCoreErrorDomain = @"com.nightvibes33.rpcs3.dynamiccore";




@interface RPCS3RuntimePatchRecord ()
- (instancetype)initWithInfo:(const rpcs3_ios_runtime_patch_info*)info;
@end
@implementation RPCS3RuntimePatchRecord
- (instancetype)initWithInfo:(const rpcs3_ios_runtime_patch_info*)info
{
    self = [super init];
    if (!self) return nil;
    auto str = [](const char* value) -> NSString* {
        return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    };
    _enabled = info->enabled != 0;
    _configurableCount = info->configurable_count;
    _hashValue = str(info->hash);
    _title = str(info->title);
    _patchDescription = str(info->description);
    _patchVersion = str(info->patch_version);
    _author = str(info->author);
    _notes = str(info->notes);
    _patchGroup = str(info->patch_group);
    _appVersion = str(info->app_version);
    return self;
}
@end

@interface RPCS3SettingOptionRecord ()
@property(nonatomic, readwrite) NSString *value;
@property(nonatomic, readwrite) NSString *label;
@end
@implementation RPCS3SettingOptionRecord
@end

@interface RPCS3SettingRecord ()
@property(nonatomic, readwrite) uint32_t kind;
@property(nonatomic, readwrite) NSString *key;
@property(nonatomic, readwrite) NSString *category;
@property(nonatomic, readwrite) NSString *section;
@property(nonatomic, readwrite) NSString *name;
@property(nonatomic, readwrite) NSString *settingDescription;
@property(nonatomic, readwrite) NSString *value;
@property(nonatomic, readwrite) NSString *defaultValue;
@property(nonatomic, readwrite) double minimum;
@property(nonatomic, readwrite) double maximum;
@property(nonatomic, readwrite) double step;
@property(nonatomic, readwrite) NSString *recommendedValue;
@property(nonatomic, readwrite) NSArray<RPCS3SettingOptionRecord *> *options;
@property(nonatomic, strong) NSMutableArray<RPCS3SettingOptionRecord *> *mutableOptions;
- (instancetype)initWithInfo:(const rpcs3_ios_setting_info*)info;
@end
@implementation RPCS3SettingRecord
- (instancetype)initWithInfo:(const rpcs3_ios_setting_info*)info
{
    self = [super init];
    if (!self) return nil;
    auto str = [](const char* value) -> NSString* {
        return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    };
    _kind = info->kind;
    _key = str(info->key);
    _category = str(info->category);
    _section = str(info->section);
    _name = str(info->name);
    _settingDescription = str(info->description);
    _value = str(info->value);
    _defaultValue = str(info->default_value);
    _minimum = info->minimum;
    _maximum = info->maximum;
    _step = info->step;
    _recommendedValue = str(info->recommended_value);
    _mutableOptions = [NSMutableArray array];
    _options = @[];
    return self;
}
- (void)freezeOptions
{
    self.options = [self.mutableOptions copy];
}
@end

@interface RPCS3SettingsSnapshot ()
@property(nonatomic, readwrite) NSArray<RPCS3SettingRecord *> *settings;
@property(nonatomic, readwrite) BOOL hasCustomConfig;
@end
@implementation RPCS3SettingsSnapshot
@end

@interface RPCS3SettingsCollector : NSObject
@property(nonatomic, strong) NSMutableArray<RPCS3SettingRecord *> *records;
@property(nonatomic, strong) NSMutableDictionary<NSString*, RPCS3SettingRecord*> *byKey;
@end
@implementation RPCS3SettingsCollector
- (instancetype)init
{
    self = [super init];
    if (self)
    {
        _records = [NSMutableArray array];
        _byKey = [NSMutableDictionary dictionary];
    }
    return self;
}
@end

@interface RPCS3BootProgressRecord ()
@property(nonatomic, readwrite) BOOL valid;
@property(nonatomic, readwrite) uint32_t completed;
@property(nonatomic, readwrite) uint32_t total;
@property(nonatomic, readwrite) NSString *stage;
@end
@implementation RPCS3BootProgressRecord
@end

@interface RPCS3PerformanceRecord ()
@property(nonatomic, readwrite) BOOL fpsValid;
@property(nonatomic, readwrite) BOOL cpuValid;
@property(nonatomic, readwrite) BOOL gpuValid;
@property(nonatomic, readwrite) BOOL memoryValid;
@property(nonatomic, readwrite) double framesPerSecond;
@property(nonatomic, readwrite) double cpuUsagePercent;
@property(nonatomic, readwrite) double gpuUsagePercent;
@property(nonatomic, readwrite) uint64_t memoryUsedBytes;
@property(nonatomic, readwrite) uint64_t memoryTotalBytes;
@end
@implementation RPCS3PerformanceRecord
@end


@interface RPCS3SavestateRecord ()
- (instancetype)initWithInfo:(const rpcs3_ios_savestate_info*)info;
@end
@implementation RPCS3SavestateRecord
- (instancetype)initWithInfo:(const rpcs3_ios_savestate_info*)info
{
    self = [super init];
    if (!self) return nil;
    _compatible = info->compatible != 0;
    _size = info->size;
    _modifiedTime = info->modified_time;
    _identifier = info->identifier ? ([NSString stringWithUTF8String:info->identifier] ?: @"") : @"";
    return self;
}
@end

@interface RPCS3TrophyRecord ()
- (instancetype)initWithInfo:(const rpcs3_ios_trophy_info*)info;
@end
@implementation RPCS3TrophyRecord
- (instancetype)initWithInfo:(const rpcs3_ios_trophy_info*)info
{
    self = [super init];
    if (!self) return nil;
    auto str = [](const char* value) -> NSString* {
        return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    };
    _trophyID = info->trophy_id;
    _displayOrder = info->display_order;
    _grade = info->grade;
    _earned = info->earned != 0;
    _hidden = info->hidden != 0;
    _unlockTimestamp = info->unlock_timestamp;
    _trophySetID = str(info->trophy_set_id);
    _gameTitle = str(info->game_title);
    _name = str(info->name);
    _trophyDescription = str(info->description);
    _iconPath = str(info->icon_path);
    return self;
}
@end

@interface RPCS3GameRecord (Internal)
- (instancetype)initWithInfo:(const rpcs3_ios_game_info*)info;
@end

namespace
{
struct RPCS3API
{
    decltype(&rpcs3_ios_abi_version) abi_version = nullptr;
    decltype(&rpcs3_ios_build_info) build_info = nullptr;
    decltype(&rpcs3_ios_initialize) initialize = nullptr;
    decltype(&rpcs3_ios_run_llvm_self_test) run_llvm_self_test = nullptr;
    decltype(&rpcs3_ios_firmware_version) firmware_version = nullptr;
    decltype(&rpcs3_ios_install_firmware) install_firmware = nullptr;
    decltype(&rpcs3_ios_install_package) install_package = nullptr;
    decltype(&rpcs3_ios_install_rap) install_rap = nullptr;
    decltype(&rpcs3_ios_install_iso) install_iso = nullptr;
    decltype(&rpcs3_ios_install_zip) install_zip = nullptr;
    decltype(&rpcs3_ios_install_folder) install_folder = nullptr;
    decltype(&rpcs3_ios_enumerate_games) enumerate_games = nullptr;
    decltype(&rpcs3_ios_enumerate_savestates) enumerate_savestates = nullptr;
    decltype(&rpcs3_ios_enumerate_trophies) enumerate_trophies = nullptr;
    decltype(&rpcs3_ios_set_display_surface) set_display_surface = nullptr;
    decltype(&rpcs3_ios_set_pad_state) set_pad_state = nullptr;
    decltype(&rpcs3_ios_boot_big_picture_mode) boot_big_picture_mode = nullptr;
    decltype(&rpcs3_ios_boot_vsh) boot_vsh = nullptr;
    decltype(&rpcs3_ios_boot_game) boot_game = nullptr;
    decltype(&rpcs3_ios_get_emulation_state) get_emulation_state = nullptr;
    decltype(&rpcs3_ios_get_boot_progress) get_boot_progress = nullptr;
    decltype(&rpcs3_ios_get_performance_metrics) get_performance_metrics = nullptr;
    decltype(&rpcs3_ios_enumerate_runtime_patches) enumerate_runtime_patches = nullptr;
    decltype(&rpcs3_ios_set_runtime_patch_enabled) set_runtime_patch_enabled = nullptr;
    decltype(&rpcs3_ios_enumerate_settings) enumerate_settings = nullptr;
    decltype(&rpcs3_ios_set_setting) set_setting = nullptr;
    decltype(&rpcs3_ios_reset_settings) reset_settings = nullptr;
    decltype(&rpcs3_ios_enumerate_game_settings) enumerate_game_settings = nullptr;
    decltype(&rpcs3_ios_set_game_setting) set_game_setting = nullptr;
    decltype(&rpcs3_ios_reset_game_settings) reset_game_settings = nullptr;
    decltype(&rpcs3_ios_remove_game_settings) remove_game_settings = nullptr;
    decltype(&rpcs3_ios_pause_emulation) pause_emulation = nullptr;
    decltype(&rpcs3_ios_resume_emulation) resume_emulation = nullptr;
    decltype(&rpcs3_ios_stop_emulation) stop_emulation = nullptr;
    decltype(&rpcs3_ios_shutdown) shutdown = nullptr;
    decltype(&rpcs3_ios_last_error) last_error = nullptr;
};

void host_log(void*, int32_t level, const char* message)
{
    if (!message) return;
    os_log_with_type(OS_LOG_DEFAULT,
        level <= 1 ? OS_LOG_TYPE_ERROR : (level <= 3 ? OS_LOG_TYPE_DEFAULT : OS_LOG_TYPE_INFO),
        "RPCS3Core: %{public}s", message);
}

void host_main_thread(void*, rpcs3_ios_main_thread_task task, void* task_context)
{
    if (!task) return;
    if ([NSThread isMainThread])
    {
        task(task_context);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        task(task_context);
    });
}

template <typename T>
bool load_symbol(void* handle, const char* name, T& output)
{
    output = reinterpret_cast<T>(dlsym(handle, name));
    return output != nullptr;
}





static void collect_runtime_patch(void* user_context, const rpcs3_ios_runtime_patch_info* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_runtime_patch_info))
        return;
    NSMutableArray<RPCS3RuntimePatchRecord*>* records =
        (__bridge NSMutableArray<RPCS3RuntimePatchRecord*>*)user_context;
    RPCS3RuntimePatchRecord* record = [[RPCS3RuntimePatchRecord alloc] initWithInfo:info];
    if (record) [records addObject:record];
}

static void collect_setting(void* user_context, const rpcs3_ios_setting_info* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_setting_info))
        return;
    RPCS3SettingsCollector* collector = (__bridge RPCS3SettingsCollector*)user_context;
    RPCS3SettingRecord* record = [[RPCS3SettingRecord alloc] initWithInfo:info];
    if (!record || record.key.length == 0) return;
    [collector.records addObject:record];
    collector.byKey[record.key] = record;
}

static void collect_setting_option(void* user_context, const rpcs3_ios_setting_option* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_setting_option) || !info->setting_key)
        return;
    RPCS3SettingsCollector* collector = (__bridge RPCS3SettingsCollector*)user_context;
    NSString* key = [NSString stringWithUTF8String:info->setting_key] ?: @"";
    RPCS3SettingRecord* setting = collector.byKey[key];
    if (!setting) return;

    RPCS3SettingOptionRecord* option = [[RPCS3SettingOptionRecord alloc] init];
    option.value = info->value ? ([NSString stringWithUTF8String:info->value] ?: @"") : @"";
    option.label = info->label ? ([NSString stringWithUTF8String:info->label] ?: option.value) : option.value;
    [setting.mutableOptions addObject:option];
}

static RPCS3SettingsSnapshot* finish_settings_snapshot(RPCS3SettingsCollector* collector, BOOL hasCustomConfig)
{
    for (RPCS3SettingRecord* record in collector.records)
        [record freezeOptions];
    RPCS3SettingsSnapshot* snapshot = [[RPCS3SettingsSnapshot alloc] init];
    snapshot.settings = [collector.records copy];
    snapshot.hasCustomConfig = hasCustomConfig;
    return snapshot;
}

static void collect_savestate(void* user_context, const rpcs3_ios_savestate_info* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_savestate_info))
        return;
    NSMutableArray<RPCS3SavestateRecord*>* records =
        (__bridge NSMutableArray<RPCS3SavestateRecord*>*)user_context;
    RPCS3SavestateRecord* record = [[RPCS3SavestateRecord alloc] initWithInfo:info];
    if (record) [records addObject:record];
}

static void collect_trophy(void* user_context, const rpcs3_ios_trophy_info* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_trophy_info))
        return;
    NSMutableArray<RPCS3TrophyRecord*>* records =
        (__bridge NSMutableArray<RPCS3TrophyRecord*>*)user_context;
    RPCS3TrophyRecord* record = [[RPCS3TrophyRecord alloc] initWithInfo:info];
    if (record) [records addObject:record];
}

static void collect_game(void* user_context, const rpcs3_ios_game_info* game)
{
    if (!user_context || !game || game->struct_size < sizeof(rpcs3_ios_game_info))
        return;
    NSMutableArray<RPCS3GameRecord*>* records =
        (__bridge NSMutableArray<RPCS3GameRecord*>*)user_context;
    RPCS3GameRecord* record = [[RPCS3GameRecord alloc] initWithInfo:game];
    if (record) [records addObject:record];
}

NSError* make_error(NSInteger code, NSString* message)
{
    return [NSError errorWithDomain:RPCS3DynamicCoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"RPCS3Core operation failed"}];
}
}


@implementation RPCS3GameRecord
- (instancetype)initWithInfo:(const rpcs3_ios_game_info*)info
{
    self = [super init];
    if (!self) return nil;
    auto stringOrEmpty = [](const char* value) -> NSString* {
        return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    };
    _titleID = stringOrEmpty(info->title_id);
    _title = stringOrEmpty(info->title);
    _version = stringOrEmpty(info->version);
    _category = stringOrEmpty(info->category);
    _iconPath = stringOrEmpty(info->icon_path);
    _firmwareVersion = stringOrEmpty(info->firmware_version);
    _path = stringOrEmpty(info->path);
    _bootable = info->bootable != 0;
    _sizeOnDisk = info->size_on_disk;
    return self;
}
@end

@interface RPCS3DynamicCore ()
{
    void* _handle;
    RPCS3API _api;
    BOOL _loaded;
    BOOL _ready;
    NSString* _buildInfo;
    NSString* _lastError;
}

@end

@implementation RPCS3DynamicCore

+ (instancetype)shared
{
    static RPCS3DynamicCore* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[RPCS3DynamicCore alloc] init];
    });
    return instance;
}

- (BOOL)isLoaded { @synchronized (self) { return _loaded; } }
- (BOOL)isReady { @synchronized (self) { return _ready; } }
- (NSString*)buildInfo { @synchronized (self) { return _buildInfo ?: @""; } }
- (NSString*)lastError { @synchronized (self) { return _lastError ?: @""; } }

- (void)setFailure:(NSString*)message
{
    @synchronized (self)
    {
        _lastError = [message copy] ?: @"Unknown RPCS3Core failure";
    }
}

- (NSString*)coreError
{
    if (_api.last_error)
    {
        const char* value = _api.last_error();
        if (value && *value)
            return [NSString stringWithUTF8String:value] ?: @"RPCS3Core returned an invalid error string";
    }
    const char* dynamicError = dlerror();
    if (dynamicError && *dynamicError)
        return [NSString stringWithUTF8String:dynamicError] ?: @"dlerror returned invalid UTF-8";
    return self.lastError.length ? self.lastError : @"RPCS3Core operation failed";
}

- (BOOL)statusOK:(rpcs3_ios_status)status
       operation:(NSString*)operation
           error:(NSError**)error
{
    if (status == RPCS3_IOS_OK)
        return YES;

    NSString* detail = [self coreError];
    NSString* message = [NSString stringWithFormat:@"%@ failed (%d): %@", operation, status, detail];
    [self setFailure:message];
    if (error) *error = make_error(status, message);
    return NO;
}

- (BOOL)resolveAPI:(NSError**)error
{
#define LOAD_API(symbol, field) \
    do { \
        if (!load_symbol(_handle, #symbol, _api.field)) { \
            NSString* message = [NSString stringWithFormat:@"RPCS3Core is missing required ABI symbol %s", #symbol]; \
            [self setFailure:message]; \
            if (error) *error = make_error(-3, message); \
            return NO; \
        } \
    } while (0)

    LOAD_API(rpcs3_ios_abi_version, abi_version);
    LOAD_API(rpcs3_ios_build_info, build_info);
    LOAD_API(rpcs3_ios_initialize, initialize);
    LOAD_API(rpcs3_ios_run_llvm_self_test, run_llvm_self_test);
    LOAD_API(rpcs3_ios_firmware_version, firmware_version);
    LOAD_API(rpcs3_ios_install_firmware, install_firmware);
    LOAD_API(rpcs3_ios_install_package, install_package);
    LOAD_API(rpcs3_ios_install_rap, install_rap);
    LOAD_API(rpcs3_ios_install_iso, install_iso);
    LOAD_API(rpcs3_ios_install_zip, install_zip);
    LOAD_API(rpcs3_ios_install_folder, install_folder);
    LOAD_API(rpcs3_ios_enumerate_games, enumerate_games);
    LOAD_API(rpcs3_ios_enumerate_savestates, enumerate_savestates);
    LOAD_API(rpcs3_ios_enumerate_trophies, enumerate_trophies);
    LOAD_API(rpcs3_ios_set_display_surface, set_display_surface);
    LOAD_API(rpcs3_ios_set_pad_state, set_pad_state);
    LOAD_API(rpcs3_ios_boot_big_picture_mode, boot_big_picture_mode);
    LOAD_API(rpcs3_ios_boot_vsh, boot_vsh);
    LOAD_API(rpcs3_ios_boot_game, boot_game);
    LOAD_API(rpcs3_ios_get_emulation_state, get_emulation_state);
    LOAD_API(rpcs3_ios_get_boot_progress, get_boot_progress);
    LOAD_API(rpcs3_ios_get_performance_metrics, get_performance_metrics);
    LOAD_API(rpcs3_ios_enumerate_runtime_patches, enumerate_runtime_patches);
    LOAD_API(rpcs3_ios_set_runtime_patch_enabled, set_runtime_patch_enabled);
    LOAD_API(rpcs3_ios_enumerate_settings, enumerate_settings);
    LOAD_API(rpcs3_ios_set_setting, set_setting);
    LOAD_API(rpcs3_ios_reset_settings, reset_settings);
    LOAD_API(rpcs3_ios_enumerate_game_settings, enumerate_game_settings);
    LOAD_API(rpcs3_ios_set_game_setting, set_game_setting);
    LOAD_API(rpcs3_ios_reset_game_settings, reset_game_settings);
    LOAD_API(rpcs3_ios_remove_game_settings, remove_game_settings);
    LOAD_API(rpcs3_ios_pause_emulation, pause_emulation);
    LOAD_API(rpcs3_ios_resume_emulation, resume_emulation);
    LOAD_API(rpcs3_ios_stop_emulation, stop_emulation);
    LOAD_API(rpcs3_ios_shutdown, shutdown);
    LOAD_API(rpcs3_ios_last_error, last_error);
#undef LOAD_API
    return YES;
}

- (BOOL)loadAndInitializeWithSupportPath:(NSString*)supportPath
                              cachePath:(NSString*)cachePath
                         jitCapacityMiB:(uint32_t)jitCapacityMiB
                                  error:(NSError**)error
{
    @synchronized (self)
    {
        if (_ready)
            return YES;
        if (_loaded)
        {
            NSString* message = @"RPCS3Core was already loaded but is not ready; relaunch is required.";
            [self setFailure:message];
            if (error) *error = make_error(-1, message);
            return NO;
        }

        if (jitCapacityMiB != 0 && jitCapacityMiB != 1 &&
            (jitCapacityMiB < 512 || jitCapacityMiB > 1024))
        {
            NSString* message = @"JIT capacity must be 0, 1, or 512–1024 MiB.";
            [self setFailure:message];
            if (error) *error = make_error(-2, message);
            return NO;
        }

        // XITRIX's JIT layer explicitly latches this process policy before any
        // RPCS3Core constructor is allowed to prepare an arena.
        const std::string jit = std::to_string(jitCapacityMiB);
        if (setenv("RPCS3_IOS_EXPANDED_JIT_ARENA", jit.c_str(), 1) != 0)
        {
            NSString* message = @"Unable to set RPCS3Core JIT arena capacity policy before loading.";
            [self setFailure:message];
            if (error) *error = make_error(errno, message);
            return NO;
        }

        NSString* frameworks = NSBundle.mainBundle.privateFrameworksPath;
        NSString* corePath = [frameworks stringByAppendingPathComponent:@"libRPCS3Core.dylib"];
        if (![[NSFileManager defaultManager] isReadableFileAtPath:corePath])
        {
            NSString* message = [NSString stringWithFormat:@"The RPCS3Core path is missing: %@", corePath];
            [self setFailure:message];
            if (error) *error = make_error(-4, message);
            return NO;
        }

        dlerror();
        _handle = dlopen(corePath.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
        if (!_handle)
        {
            NSString* message = [NSString stringWithFormat:@"Unable to load RPCS3Core: %@", [self coreError]];
            [self setFailure:message];
            if (error) *error = make_error(-5, message);
            return NO;
        }
        _loaded = YES;

        if (![self resolveAPI:error])
            return NO;

        const uint32_t abi = _api.abi_version();
        if (abi != RPCS3_IOS_ABI_VERSION)
        {
            NSString* message = [NSString stringWithFormat:
                @"RPCS3Core uses an incompatible C ABI: got %u, expected %u.", abi, RPCS3_IOS_ABI_VERSION];
            [self setFailure:message];
            if (error) *error = make_error(-6, message);
            return NO;
        }

        const char* build = _api.build_info();
        _buildInfo = build ? ([NSString stringWithUTF8String:build] ?: @"") : @"";

        rpcs3_ios_config config = {};
        config.abi_version = RPCS3_IOS_ABI_VERSION;
        config.struct_size = sizeof(config);
        config.application_support_path = supportPath.fileSystemRepresentation;
        config.cache_path = cachePath.fileSystemRepresentation;
        config.log_callback = &host_log;
        config.main_thread_callback = &host_main_thread;
        config.user_context = (__bridge void*)self;
        config.expanded_jit_arena = jitCapacityMiB;
        config.reserved = 0;

        if (![self statusOK:_api.initialize(&config) operation:@"RPCS3 Emu.Init()" error:error])
            return NO;

        uint64_t output = 0;
        if (![self statusOK:_api.run_llvm_self_test(11, &output)
                  operation:@"RPCS3 LLVM JIT self-test"
                      error:error])
            return NO;
        if (output != 40)
        {
            NSString* message = [NSString stringWithFormat:
                @"RPCS3 LLVM JIT self-test returned unexpected output %llu.", (unsigned long long)output];
            [self setFailure:message];
            if (error) *error = make_error(-7, message);
            return NO;
        }

        _ready = YES;
        _lastError = @"";
        return YES;
    }
}

- (BOOL)attachMetalLayer:(CAMetalLayer*)layer
                   width:(uint32_t)width
                  height:(uint32_t)height
             refreshRate:(float)refreshRate
                   error:(NSError**)error
{
    if (!self.ready)
    {
        if (error) *error = make_error(-8, @"RPCS3Core is not ready for a video surface.");
        return NO;
    }
    rpcs3_ios_display_surface surface = {};
    surface.struct_size = sizeof(surface);
    surface.width = std::max<uint32_t>(1, width);
    surface.height = std::max<uint32_t>(1, height);
    surface.refresh_rate = std::max(1.0f, refreshRate);
    surface.metal_layer = (__bridge void*)layer;
    return [self statusOK:_api.set_display_surface(&surface) operation:@"Attach Metal surface" error:error];
}

- (BOOL)detachDisplayWithError:(NSError**)error
{
    return [self statusOK:_api.set_display_surface(nullptr) operation:@"Detach Metal surface" error:error];
}

- (BOOL)bootBigPictureWithError:(NSError**)error
{
    return [self statusOK:_api.boot_big_picture_mode() operation:@"Big Picture Mode" error:error];
}

- (BOOL)installFirmwareAtPath:(NSString*)path error:(NSError**)error
{
    return [self statusOK:_api.install_firmware(path.fileSystemRepresentation, nullptr, nullptr)
                operation:@"Firmware installation" error:error];
}

- (BOOL)installPackageAtPath:(NSString*)path error:(NSError**)error
{
    return [self statusOK:_api.install_package(path.fileSystemRepresentation, nullptr, nullptr)
                operation:@"Package installation" error:error];
}

- (BOOL)installISOAtPath:(NSString*)path error:(NSError**)error
{
    return [self statusOK:_api.install_iso(path.fileSystemRepresentation, nullptr, nullptr, nullptr)
                operation:@"ISO installation" error:error];
}

- (BOOL)installZIPAtPath:(NSString*)path error:(NSError**)error
{
    return [self statusOK:_api.install_zip(path.fileSystemRepresentation, nullptr, nullptr)
                operation:@"ZIP installation" error:error];
}

- (BOOL)setPlayerIndex:(uint32_t)playerIndex
              connected:(BOOL)connected
                buttons:(uint64_t)buttons
                  leftX:(float)leftX
                  leftY:(float)leftY
                 rightX:(float)rightX
                 rightY:(float)rightY
            leftTrigger:(float)leftTrigger
           rightTrigger:(float)rightTrigger
{
    if (!self.ready || !_api.set_pad_state || playerIndex > 6)
        return NO;
    rpcs3_ios_pad_state state = {};
    state.struct_size = sizeof(state);
    state.connected = connected ? 1u : 0u;
    state.buttons = buttons;
    state.left_stick_x = std::clamp(leftX, -1.0f, 1.0f);
    state.left_stick_y = std::clamp(leftY, -1.0f, 1.0f);
    state.right_stick_x = std::clamp(rightX, -1.0f, 1.0f);
    state.right_stick_y = std::clamp(rightY, -1.0f, 1.0f);
    state.left_trigger = std::clamp(leftTrigger, 0.0f, 1.0f);
    state.right_trigger = std::clamp(rightTrigger, 0.0f, 1.0f);
    return _api.set_pad_state(playerIndex, &state) == RPCS3_IOS_OK;
}

- (BOOL)setPlayerOneConnected:(BOOL)connected
                      buttons:(uint64_t)buttons
                        leftX:(float)leftX
                        leftY:(float)leftY
                       rightX:(float)rightX
                       rightY:(float)rightY
                  leftTrigger:(float)leftTrigger
                 rightTrigger:(float)rightTrigger
{
    return [self setPlayerIndex:0
                     connected:connected
                       buttons:buttons
                         leftX:leftX
                         leftY:leftY
                        rightX:rightX
                        rightY:rightY
                   leftTrigger:leftTrigger
                  rightTrigger:rightTrigger];
}

- (BOOL)pauseWithError:(NSError**)error
{
    return [self statusOK:_api.pause_emulation() operation:@"Pause emulation" error:error];
}

- (BOOL)resumeWithError:(NSError**)error
{
    return [self statusOK:_api.resume_emulation() operation:@"Resume emulation" error:error];
}

- (BOOL)stopWithError:(NSError**)error
{
    return [self statusOK:_api.stop_emulation() operation:@"Stop emulation" error:error];
}

- (BOOL)shutdownWithError:(NSError**)error
{
    if (!_ready) return YES;
    const BOOL ok = [self statusOK:_api.shutdown() operation:@"RPCS3Core shutdown" error:error];
    if (ok)
    {
        @synchronized (self) { _ready = NO; }
    }
    return ok;
}

- (BOOL)startWithSupportPath:(NSString*)supportPath
                  cachePath:(NSString*)cachePath
             jitCapacityMiB:(uint32_t)jitCapacityMiB
{
    return [self loadAndInitializeWithSupportPath:supportPath
                                       cachePath:cachePath
                                  jitCapacityMiB:jitCapacityMiB
                                           error:nullptr];
}

- (BOOL)attachMetalLayer:(CAMetalLayer*)layer
                   width:(uint32_t)width
                  height:(uint32_t)height
             refreshRate:(float)refreshRate
{
    return [self attachMetalLayer:layer width:width height:height refreshRate:refreshRate error:nullptr];
}

- (BOOL)detachDisplay
{
    return [self detachDisplayWithError:nullptr];
}

- (BOOL)bootBigPicture
{
    return [self bootBigPictureWithError:nullptr];
}

- (BOOL)bootXMB
{
    if (!self.ready || !_api.boot_vsh)
        return NO;
    return [self statusOK:_api.boot_vsh() operation:@"PlayStation 3 XMB" error:nullptr];
}

- (BOOL)installContentAtPath:(NSString*)path
{
    NSString* ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"pup"])
        return [self installFirmwareAtPath:path error:nullptr];
    if ([ext isEqualToString:@"pkg"])
        return [self installPackageAtPath:path error:nullptr];
    if ([ext isEqualToString:@"rap"])
        return [self statusOK:_api.install_rap(path.fileSystemRepresentation)
                    operation:@"RAP license installation"
                        error:nullptr];
    if ([ext isEqualToString:@"iso"])
        return [self installISOAtPath:path error:nullptr];
    if ([ext isEqualToString:@"zip"])
        return [self installZIPAtPath:path error:nullptr];

    BOOL isDirectory = NO;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDirectory] && isDirectory)
        return [self statusOK:_api.install_folder(path.fileSystemRepresentation, nullptr, nullptr)
                    operation:@"Game folder installation"
                        error:nullptr];

    [self setFailure:[NSString stringWithFormat:@"Unsupported RPCS3 content type: .%@", ext]];
    return NO;
}





- (NSArray<RPCS3RuntimePatchRecord*>*)runtimePatchesForTitleID:(NSString*)titleID
                                                    appVersion:(NSString*)appVersion
{
    if (!self.ready || !_api.enumerate_runtime_patches || titleID.length == 0)
        return @[];
    NSMutableArray<RPCS3RuntimePatchRecord*>* records = [NSMutableArray array];
    const char* version = appVersion.length ? appVersion.UTF8String : nullptr;
    const rpcs3_ios_status status = _api.enumerate_runtime_patches(
        titleID.UTF8String, version, &collect_runtime_patch, (__bridge void*)records);
    if (status != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return @[];
    }
    return [records copy];
}

- (BOOL)setRuntimePatchForTitleID:(NSString*)titleID
                             hash:(NSString*)hashValue
                            title:(NSString*)title
                       appVersion:(NSString*)appVersion
                      description:(NSString*)description
                          enabled:(BOOL)enabled
{
    if (!self.ready || !_api.set_runtime_patch_enabled ||
        titleID.length == 0 || hashValue.length == 0 || title.length == 0 ||
        appVersion.length == 0 || description.length == 0)
        return NO;

    return [self statusOK:_api.set_runtime_patch_enabled(
                titleID.UTF8String,
                hashValue.UTF8String,
                title.UTF8String,
                appVersion.UTF8String,
                description.UTF8String,
                enabled ? 1u : 0u)
                operation:@"Game patch update"
                    error:nullptr];
}

- (RPCS3SettingsSnapshot*)globalSettings
{
    RPCS3SettingsCollector* collector = [[RPCS3SettingsCollector alloc] init];
    if (!self.ready || !_api.enumerate_settings)
        return finish_settings_snapshot(collector, NO);
    const rpcs3_ios_status status = _api.enumerate_settings(
        &collect_setting, &collect_setting_option, (__bridge void*)collector);
    if (status != RPCS3_IOS_OK)
        [self setFailure:[self coreError]];
    return finish_settings_snapshot(collector, NO);
}

- (RPCS3SettingsSnapshot*)gameSettingsForTitleID:(NSString*)titleID
{
    RPCS3SettingsCollector* collector = [[RPCS3SettingsCollector alloc] init];
    if (!self.ready || !_api.enumerate_game_settings || titleID.length == 0)
        return finish_settings_snapshot(collector, NO);
    uint32_t custom = 0;
    const rpcs3_ios_status status = _api.enumerate_game_settings(
        titleID.UTF8String,
        &collect_setting,
        &collect_setting_option,
        (__bridge void*)collector,
        &custom);
    if (status != RPCS3_IOS_OK)
        [self setFailure:[self coreError]];
    return finish_settings_snapshot(collector, custom != 0);
}

- (BOOL)setGlobalSettingKey:(NSString*)key value:(NSString*)value
{
    if (!self.ready || !_api.set_setting || key.length == 0)
        return NO;
    return [self statusOK:_api.set_setting(key.UTF8String, value.UTF8String)
                operation:@"Global setting update"
                    error:nullptr];
}

- (BOOL)resetGlobalSettings
{
    if (!self.ready || !_api.reset_settings)
        return NO;
    return [self statusOK:_api.reset_settings()
                operation:@"Reset global settings"
                    error:nullptr];
}

- (BOOL)setGameSettingForTitleID:(NSString*)titleID key:(NSString*)key value:(NSString*)value
{
    if (!self.ready || !_api.set_game_setting || titleID.length == 0 || key.length == 0)
        return NO;
    return [self statusOK:_api.set_game_setting(titleID.UTF8String, key.UTF8String, value.UTF8String)
                operation:@"Game setting update"
                    error:nullptr];
}

- (BOOL)resetGameSettingsForTitleID:(NSString*)titleID
{
    if (!self.ready || !_api.reset_game_settings || titleID.length == 0)
        return NO;
    return [self statusOK:_api.reset_game_settings(titleID.UTF8String)
                operation:@"Reset game settings"
                    error:nullptr];
}

- (BOOL)removeGameSettingsForTitleID:(NSString*)titleID
{
    if (!self.ready || !_api.remove_game_settings || titleID.length == 0)
        return NO;
    return [self statusOK:_api.remove_game_settings(titleID.UTF8String)
                operation:@"Remove game settings"
                    error:nullptr];
}

- (RPCS3BootProgressRecord*)bootProgress
{
    RPCS3BootProgressRecord* record = [[RPCS3BootProgressRecord alloc] init];
    record.stage = @"";
    if (!self.ready || !_api.get_boot_progress)
        return record;

    uint32_t completed = 0;
    uint32_t total = 0;
    char stage[1024] = {};
    const rpcs3_ios_status status = _api.get_boot_progress(
        &completed, &total, stage, sizeof(stage));
    if (status != RPCS3_IOS_OK)
        return record;

    record.valid = YES;
    record.completed = completed;
    record.total = total;
    record.stage = stage[0] ? ([NSString stringWithUTF8String:stage] ?: @"") : @"";
    return record;
}

- (RPCS3PerformanceRecord*)performanceMetrics
{
    RPCS3PerformanceRecord* record = [[RPCS3PerformanceRecord alloc] init];
    if (!self.ready || !_api.get_performance_metrics)
        return record;

    rpcs3_ios_performance_metrics metrics = {};
    metrics.struct_size = sizeof(metrics);
    if (_api.get_performance_metrics(&metrics) != RPCS3_IOS_OK)
        return record;

    record.fpsValid = (metrics.valid_fields & RPCS3_IOS_PERFORMANCE_FPS_VALID) != 0;
    record.cpuValid = (metrics.valid_fields & RPCS3_IOS_PERFORMANCE_CPU_VALID) != 0;
    record.gpuValid = (metrics.valid_fields & RPCS3_IOS_PERFORMANCE_GPU_VALID) != 0;
    record.memoryValid = (metrics.valid_fields & RPCS3_IOS_PERFORMANCE_MEMORY_VALID) != 0;
    record.framesPerSecond = metrics.frames_per_second;
    record.cpuUsagePercent = metrics.cpu_usage_percent;
    record.gpuUsagePercent = metrics.gpu_usage_percent;
    record.memoryUsedBytes = metrics.memory_used_bytes;
    record.memoryTotalBytes = metrics.memory_total_bytes;
    return record;
}

- (NSArray<RPCS3GameRecord*>*)enumerateGames
{
    if (!self.ready || !_api.enumerate_games)
        return @[];
    NSMutableArray<RPCS3GameRecord*>* records = [NSMutableArray array];
    const rpcs3_ios_status status = _api.enumerate_games(
        &collect_game, (__bridge void*)records);
    if (status != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return @[];
    }
    return [records copy];
}


- (NSArray<RPCS3SavestateRecord*>*)enumerateSavestatesForTitleID:(NSString*)titleID
{
    if (!self.ready || !_api.enumerate_savestates || titleID.length == 0)
        return @[];
    NSMutableArray<RPCS3SavestateRecord*>* records = [NSMutableArray array];
    const rpcs3_ios_status status = _api.enumerate_savestates(
        titleID.UTF8String, &collect_savestate, (__bridge void*)records);
    if (status != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return @[];
    }
    return [records copy];
}

- (NSArray<RPCS3TrophyRecord*>*)enumerateTrophiesForTitleID:(NSString*)titleID
{
    if (!self.ready || !_api.enumerate_trophies || titleID.length == 0)
        return @[];
    NSMutableArray<RPCS3TrophyRecord*>* records = [NSMutableArray array];
    const rpcs3_ios_status status = _api.enumerate_trophies(
        titleID.UTF8String, &collect_trophy, (__bridge void*)records);
    if (status != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return @[];
    }
    return [records copy];
}

- (BOOL)bootGameWithTitleID:(NSString*)titleID
{
    return [self bootGameWithTitleID:titleID savestateID:@""];
}

- (BOOL)bootGameWithTitleID:(NSString*)titleID savestateID:(NSString*)savestateID
{
    if (!self.ready || !_api.boot_game || titleID.length == 0)
        return NO;
    const char* state = savestateID.length ? savestateID.UTF8String : nullptr;
    return [self statusOK:_api.boot_game(titleID.UTF8String, state)
                operation:@"Game boot"
                    error:nullptr];
}

- (BOOL)pause { return [self pauseWithError:nullptr]; }
- (BOOL)resume { return [self resumeWithError:nullptr]; }
- (BOOL)stop { return [self stopWithError:nullptr]; }
- (BOOL)shutdown { return [self shutdownWithError:nullptr]; }



@end
