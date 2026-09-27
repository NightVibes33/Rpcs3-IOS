#import "RPCS3DynamicCore.h"
#include "RPCS3IOS.h"

#import <dlfcn.h>
#import <os/log.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>

static NSString * const RPCS3DynamicCoreErrorDomain = @"com.nightvibes33.rpcs3.dynamiccore";





@interface RPCS3RPCNConfigRecord ()
@property(nonatomic, readwrite) BOOL hasPassword;
@property(nonatomic, readwrite) BOOL hasToken;
@property(nonatomic, readwrite) BOOL ipv6Support;
@property(nonatomic, readwrite) BOOL connected;
@property(nonatomic, readwrite) BOOL authenticated;
@property(nonatomic, readwrite) NSString *username;
@property(nonatomic, readwrite) NSString *host;
@property(nonatomic, readwrite) NSString *onlineName;
@property(nonatomic, readwrite) NSString *avatarURL;
@end
@implementation RPCS3RPCNConfigRecord
@end

@interface RPCS3RPCNServerRecord ()
@property(nonatomic, readwrite) BOOL selected;
@property(nonatomic, readwrite) BOOL removable;
@property(nonatomic, readwrite) NSString *serverDescription;
@property(nonatomic, readwrite) NSString *host;
@end
@implementation RPCS3RPCNServerRecord
@end

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
    _patchHash = str(info->hash);
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


@interface RPCS3GamePatchRecord ()
- (instancetype)initWithInfo:(const rpcs3_ios_game_patch_info*)info;
@end
@implementation RPCS3GamePatchRecord
- (instancetype)initWithInfo:(const rpcs3_ios_game_patch_info*)info
{
    self = [super init];
    if (!self) return nil;
    auto str = [](const char* value) -> NSString* {
        return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    };
    _titleID = str(info->title_id);
    _title = str(info->title);
    _version = str(info->version);
    return self;
}
@end

@interface RPCS3GameCacheRecord ()
@property(nonatomic, readwrite) uint64_t shaderBytes;
@property(nonatomic, readwrite) uint64_t ppuBytes;
@property(nonatomic, readwrite) uint64_t spuBytes;
@property(nonatomic, readwrite) uint64_t hdd1Bytes;
@property(nonatomic, readwrite) uint64_t totalBytes;
@end
@implementation RPCS3GameCacheRecord
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
    decltype(&rpcs3_ios_update_config_database) update_config_database = nullptr;
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
    decltype(&rpcs3_ios_get_rpcn_config) get_rpcn_config = nullptr;
    decltype(&rpcs3_ios_enumerate_rpcn_servers) enumerate_rpcn_servers = nullptr;
    decltype(&rpcs3_ios_set_rpcn_server) set_rpcn_server = nullptr;
    decltype(&rpcs3_ios_add_rpcn_server) add_rpcn_server = nullptr;
    decltype(&rpcs3_ios_remove_rpcn_server) remove_rpcn_server = nullptr;
    decltype(&rpcs3_ios_set_rpcn_credentials) set_rpcn_credentials = nullptr;
    decltype(&rpcs3_ios_test_rpcn_account) test_rpcn_account = nullptr;
    decltype(&rpcs3_ios_enumerate_runtime_patches) enumerate_runtime_patches = nullptr;
    decltype(&rpcs3_ios_set_runtime_patch_enabled) set_runtime_patch_enabled = nullptr;
    decltype(&rpcs3_ios_enumerate_settings) enumerate_settings = nullptr;
    decltype(&rpcs3_ios_set_setting) set_setting = nullptr;
    decltype(&rpcs3_ios_reset_settings) reset_settings = nullptr;
    decltype(&rpcs3_ios_enumerate_game_settings) enumerate_game_settings = nullptr;
    decltype(&rpcs3_ios_set_game_setting) set_game_setting = nullptr;
    decltype(&rpcs3_ios_reset_game_settings) reset_game_settings = nullptr;
    decltype(&rpcs3_ios_remove_game_settings) remove_game_settings = nullptr;
    decltype(&rpcs3_ios_install_game_patch) install_game_patch = nullptr;
    decltype(&rpcs3_ios_fetch_game_update_manifest) fetch_game_update_manifest = nullptr;
    decltype(&rpcs3_ios_download_game_update_package) download_game_update_package = nullptr;
    decltype(&rpcs3_ios_duplicate_savestate) duplicate_savestate = nullptr;
    decltype(&rpcs3_ios_delete_savestate) delete_savestate = nullptr;
    decltype(&rpcs3_ios_import_savestate) import_savestate = nullptr;
    decltype(&rpcs3_ios_export_savestate) export_savestate = nullptr;
    decltype(&rpcs3_ios_delete_game) delete_game = nullptr;
    decltype(&rpcs3_ios_get_game_cache_info) get_game_cache_info = nullptr;
    decltype(&rpcs3_ios_clear_game_cache) clear_game_cache = nullptr;
    decltype(&rpcs3_ios_enumerate_game_patches) enumerate_game_patches = nullptr;
    decltype(&rpcs3_ios_get_patch_repository_url) get_patch_repository_url = nullptr;
    decltype(&rpcs3_ios_install_patch_repository) install_patch_repository = nullptr;
    decltype(&rpcs3_ios_enumerate_game_settings_presets) enumerate_game_settings_presets = nullptr;
    decltype(&rpcs3_ios_save_game_settings_preset) save_game_settings_preset = nullptr;
    decltype(&rpcs3_ios_apply_game_settings_preset) apply_game_settings_preset = nullptr;
    decltype(&rpcs3_ios_duplicate_game_settings_preset) duplicate_game_settings_preset = nullptr;
    decltype(&rpcs3_ios_rename_game_settings_preset) rename_game_settings_preset = nullptr;
    decltype(&rpcs3_ios_delete_game_settings_preset) delete_game_settings_preset = nullptr;
    decltype(&rpcs3_ios_import_game_settings_preset) import_game_settings_preset = nullptr;
    decltype(&rpcs3_ios_export_game_settings_preset) export_game_settings_preset = nullptr;
    decltype(&rpcs3_ios_create_rpcn_account) create_rpcn_account = nullptr;
    decltype(&rpcs3_ios_resend_rpcn_token) resend_rpcn_token = nullptr;
    decltype(&rpcs3_ios_request_rpcn_password_reset) request_rpcn_password_reset = nullptr;
    decltype(&rpcs3_ios_reset_rpcn_password) reset_rpcn_password = nullptr;
    decltype(&rpcs3_ios_delete_rpcn_account) delete_rpcn_account = nullptr;
    decltype(&rpcs3_ios_enumerate_rpcn_social) enumerate_rpcn_social = nullptr;
    decltype(&rpcs3_ios_perform_rpcn_social_action) perform_rpcn_social_action = nullptr;
    decltype(&rpcs3_ios_get_pad_feedback) get_pad_feedback = nullptr;
    decltype(&rpcs3_ios_get_state) get_state = nullptr;
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






static void collect_rpcn_config(void* user_context, const rpcs3_ios_rpcn_config_info* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_rpcn_config_info))
        return;
    RPCS3RPCNConfigRecord* record = (__bridge RPCS3RPCNConfigRecord*)user_context;
    auto str = [](const char* value) -> NSString* {
        return value ? ([NSString stringWithUTF8String:value] ?: @"") : @"";
    };
    record.hasPassword = info->has_password != 0;
    record.hasToken = info->has_token != 0;
    record.ipv6Support = info->ipv6_support != 0;
    record.connected = info->connected != 0;
    record.authenticated = info->authenticated != 0;
    record.username = str(info->username);
    record.host = str(info->host);
    record.onlineName = str(info->online_name);
    record.avatarURL = str(info->avatar_url);
}

static void collect_rpcn_server(void* user_context, const rpcs3_ios_rpcn_server_info* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_rpcn_server_info))
        return;
    NSMutableArray<RPCS3RPCNServerRecord*>* records =
        (__bridge NSMutableArray<RPCS3RPCNServerRecord*>*)user_context;
    RPCS3RPCNServerRecord* record = [[RPCS3RPCNServerRecord alloc] init];
    record.selected = info->selected != 0;
    record.removable = info->removable != 0;
    record.serverDescription = info->description ? ([NSString stringWithUTF8String:info->description] ?: @"") : @"";
    record.host = info->host ? ([NSString stringWithUTF8String:info->host] ?: @"") : @"";
    [records addObject:record];
}


static void collect_game_patch(void* user_context, const rpcs3_ios_game_patch_info* info)
{
    if (!user_context || !info || info->struct_size < sizeof(rpcs3_ios_game_patch_info))
        return;
    NSMutableArray<RPCS3GamePatchRecord*>* records =
        (__bridge NSMutableArray<RPCS3GamePatchRecord*>*)user_context;
    RPCS3GamePatchRecord* record = [[RPCS3GamePatchRecord alloc] initWithInfo:info];
    if (record) [records addObject:record];
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
    LOAD_API(rpcs3_ios_update_config_database, update_config_database);
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
    LOAD_API(rpcs3_ios_get_rpcn_config, get_rpcn_config);
    LOAD_API(rpcs3_ios_enumerate_rpcn_servers, enumerate_rpcn_servers);
    LOAD_API(rpcs3_ios_set_rpcn_server, set_rpcn_server);
    LOAD_API(rpcs3_ios_add_rpcn_server, add_rpcn_server);
    LOAD_API(rpcs3_ios_remove_rpcn_server, remove_rpcn_server);
    LOAD_API(rpcs3_ios_set_rpcn_credentials, set_rpcn_credentials);
    LOAD_API(rpcs3_ios_test_rpcn_account, test_rpcn_account);
    LOAD_API(rpcs3_ios_enumerate_runtime_patches, enumerate_runtime_patches);
    LOAD_API(rpcs3_ios_set_runtime_patch_enabled, set_runtime_patch_enabled);
    LOAD_API(rpcs3_ios_enumerate_settings, enumerate_settings);
    LOAD_API(rpcs3_ios_set_setting, set_setting);
    LOAD_API(rpcs3_ios_reset_settings, reset_settings);
    LOAD_API(rpcs3_ios_enumerate_game_settings, enumerate_game_settings);
    LOAD_API(rpcs3_ios_set_game_setting, set_game_setting);
    LOAD_API(rpcs3_ios_reset_game_settings, reset_game_settings);
    LOAD_API(rpcs3_ios_remove_game_settings, remove_game_settings);
    LOAD_API(rpcs3_ios_install_game_patch, install_game_patch);
    LOAD_API(rpcs3_ios_fetch_game_update_manifest, fetch_game_update_manifest);
    LOAD_API(rpcs3_ios_download_game_update_package, download_game_update_package);
    LOAD_API(rpcs3_ios_duplicate_savestate, duplicate_savestate);
    LOAD_API(rpcs3_ios_delete_savestate, delete_savestate);
    LOAD_API(rpcs3_ios_import_savestate, import_savestate);
    LOAD_API(rpcs3_ios_export_savestate, export_savestate);
    LOAD_API(rpcs3_ios_delete_game, delete_game);
    LOAD_API(rpcs3_ios_get_game_cache_info, get_game_cache_info);
    LOAD_API(rpcs3_ios_clear_game_cache, clear_game_cache);
    LOAD_API(rpcs3_ios_enumerate_game_patches, enumerate_game_patches);
    LOAD_API(rpcs3_ios_get_patch_repository_url, get_patch_repository_url);
    LOAD_API(rpcs3_ios_install_patch_repository, install_patch_repository);
    LOAD_API(rpcs3_ios_enumerate_game_settings_presets, enumerate_game_settings_presets);
    LOAD_API(rpcs3_ios_save_game_settings_preset, save_game_settings_preset);
    LOAD_API(rpcs3_ios_apply_game_settings_preset, apply_game_settings_preset);
    LOAD_API(rpcs3_ios_duplicate_game_settings_preset, duplicate_game_settings_preset);
    LOAD_API(rpcs3_ios_rename_game_settings_preset, rename_game_settings_preset);
    LOAD_API(rpcs3_ios_delete_game_settings_preset, delete_game_settings_preset);
    LOAD_API(rpcs3_ios_import_game_settings_preset, import_game_settings_preset);
    LOAD_API(rpcs3_ios_export_game_settings_preset, export_game_settings_preset);
    LOAD_API(rpcs3_ios_create_rpcn_account, create_rpcn_account);
    LOAD_API(rpcs3_ios_resend_rpcn_token, resend_rpcn_token);
    LOAD_API(rpcs3_ios_request_rpcn_password_reset, request_rpcn_password_reset);
    LOAD_API(rpcs3_ios_reset_rpcn_password, reset_rpcn_password);
    LOAD_API(rpcs3_ios_delete_rpcn_account, delete_rpcn_account);
    LOAD_API(rpcs3_ios_enumerate_rpcn_social, enumerate_rpcn_social);
    LOAD_API(rpcs3_ios_perform_rpcn_social_action, perform_rpcn_social_action);
    LOAD_API(rpcs3_ios_get_pad_feedback, get_pad_feedback);
    LOAD_API(rpcs3_ios_get_state, get_state);
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







- (RPCS3RPCNConfigRecord*)rpcnConfig
{
    RPCS3RPCNConfigRecord* record = [[RPCS3RPCNConfigRecord alloc] init];
    record.username = @"";
    record.host = @"";
    record.onlineName = @"";
    record.avatarURL = @"";
    if (!self.ready || !_api.get_rpcn_config)
        return record;
    const rpcs3_ios_status status = _api.get_rpcn_config(
        &collect_rpcn_config, (__bridge void*)record);
    if (status != RPCS3_IOS_OK)
        [self setFailure:[self coreError]];
    return record;
}

- (NSArray<RPCS3RPCNServerRecord*>*)rpcnServers
{
    if (!self.ready || !_api.enumerate_rpcn_servers)
        return @[];
    NSMutableArray<RPCS3RPCNServerRecord*>* records = [NSMutableArray array];
    const rpcs3_ios_status status = _api.enumerate_rpcn_servers(
        &collect_rpcn_server, (__bridge void*)records);
    if (status != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return @[];
    }
    return [records copy];
}

- (BOOL)setRPCNServerHost:(NSString*)host
{
    if (!self.ready || !_api.set_rpcn_server || host.length == 0)
        return NO;
    return [self statusOK:_api.set_rpcn_server(host.UTF8String)
                operation:@"RPCN server selection"
                    error:nullptr];
}

- (BOOL)addRPCNServerDescription:(NSString*)description host:(NSString*)host
{
    if (!self.ready || !_api.add_rpcn_server || description.length == 0 || host.length == 0)
        return NO;
    return [self statusOK:_api.add_rpcn_server(description.UTF8String, host.UTF8String)
                operation:@"Add RPCN server"
                    error:nullptr];
}

- (BOOL)removeRPCNServerDescription:(NSString*)description host:(NSString*)host
{
    if (!self.ready || !_api.remove_rpcn_server || description.length == 0 || host.length == 0)
        return NO;
    return [self statusOK:_api.remove_rpcn_server(description.UTF8String, host.UTF8String)
                operation:@"Remove RPCN server"
                    error:nullptr];
}

- (BOOL)setRPCNCredentialsUsername:(NSString*)username
                          password:(NSString*)password
                             token:(NSString*)token
                              ipv6:(BOOL)ipv6
{
    if (!self.ready || !_api.set_rpcn_credentials)
        return NO;
    return [self statusOK:_api.set_rpcn_credentials(
                username.UTF8String,
                password.UTF8String,
                token.UTF8String,
                ipv6 ? 1u : 0u)
                operation:@"Save RPCN credentials"
                    error:nullptr];
}

- (BOOL)testRPCNAccount
{
    if (!self.ready || !_api.test_rpcn_account)
        return NO;
    return [self statusOK:_api.test_rpcn_account()
                operation:@"RPCN account test"
                    error:nullptr];
}

- (BOOL)updateConfigDatabaseData:(NSData*)data
{
    if (!self.ready || !_api.update_config_database || data.length == 0)
        return NO;
    return [self statusOK:_api.update_config_database(data.bytes, data.length)
                operation:@"RPCS3 configuration database update"
                    error:nullptr];
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
                             hash:(NSString*)patchHash
                            title:(NSString*)title
                       appVersion:(NSString*)appVersion
                      description:(NSString*)description
                          enabled:(BOOL)enabled
{
    if (!self.ready || !_api.set_runtime_patch_enabled ||
        titleID.length == 0 || patchHash.length == 0 || title.length == 0 ||
        appVersion.length == 0 || description.length == 0)
        return NO;

    return [self statusOK:_api.set_runtime_patch_enabled(
                titleID.UTF8String,
                patchHash.UTF8String,
                title.UTF8String,
                appVersion.UTF8String,
                description.UTF8String,
                enabled ? 1u : 0u)
                operation:@"Game patch update"
                    error:nullptr];
}


- (BOOL)installGamePatchForTitleID:(NSString*)titleID packagePath:(NSString*)packagePath
{
    if (!self.ready || !_api.install_game_patch || titleID.length == 0 || packagePath.length == 0)
        return NO;
    return [self statusOK:_api.install_game_patch(
                titleID.UTF8String, packagePath.fileSystemRepresentation, nullptr, nullptr)
                operation:@"Game-update installation"
                    error:nullptr];
}

- (NSData*)gameUpdateManifestForTitleID:(NSString*)titleID
{
    if (!self.ready || !_api.fetch_game_update_manifest || titleID.length == 0)
        return nil;

    constexpr size_t capacity = 2u * 1024u * 1024u;
    NSMutableData* data = [NSMutableData dataWithLength:capacity];
    size_t size = 0;
    const rpcs3_ios_status status = _api.fetch_game_update_manifest(
        titleID.UTF8String, data.mutableBytes, data.length, &size);
    if (status != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return nil;
    }
    if (size > data.length)
    {
        [self setFailure:@"RPCS3 returned an invalid update-manifest size."];
        return nil;
    }
    data.length = size;
    return [data copy];
}

- (BOOL)downloadGameUpdatePackageURL:(NSString*)packageURL
                     destinationPath:(NSString*)destinationPath
                        expectedSize:(uint64_t)expectedSize
{
    if (!self.ready || !_api.download_game_update_package ||
        packageURL.length == 0 || destinationPath.length == 0 || expectedSize == 0)
        return NO;
    return [self statusOK:_api.download_game_update_package(
                packageURL.UTF8String,
                destinationPath.fileSystemRepresentation,
                expectedSize,
                nullptr,
                nullptr)
                operation:@"Game update download"
                    error:nullptr];
}

- (BOOL)duplicateSavestateForTitleID:(NSString*)titleID identifier:(NSString*)identifier
{
    if (!self.ready || !_api.duplicate_savestate || titleID.length == 0 || identifier.length == 0)
        return NO;
    return [self statusOK:_api.duplicate_savestate(titleID.UTF8String, identifier.UTF8String)
                operation:@"Duplicate save state" error:nullptr];
}

- (BOOL)deleteSavestateForTitleID:(NSString*)titleID identifier:(NSString*)identifier
{
    if (!self.ready || !_api.delete_savestate || titleID.length == 0 || identifier.length == 0)
        return NO;
    return [self statusOK:_api.delete_savestate(titleID.UTF8String, identifier.UTF8String)
                operation:@"Delete save state" error:nullptr];
}

- (BOOL)importSavestateForTitleID:(NSString*)titleID sourcePath:(NSString*)sourcePath
{
    if (!self.ready || !_api.import_savestate || titleID.length == 0 || sourcePath.length == 0)
        return NO;
    return [self statusOK:_api.import_savestate(titleID.UTF8String, sourcePath.fileSystemRepresentation)
                operation:@"Import savestate" error:nullptr];
}

- (BOOL)exportSavestateForTitleID:(NSString*)titleID
                      savestateID:(NSString*)savestateID
                  destinationPath:(NSString*)destinationPath
{
    if (!self.ready || !_api.export_savestate ||
        titleID.length == 0 || savestateID.length == 0 || destinationPath.length == 0)
        return NO;
    return [self statusOK:_api.export_savestate(
                titleID.UTF8String,
                savestateID.UTF8String,
                destinationPath.fileSystemRepresentation)
                operation:@"Export savestate" error:nullptr];
}

- (BOOL)deleteGameForTitleID:(NSString*)titleID
{
    if (!self.ready || !_api.delete_game || titleID.length == 0)
        return NO;
    return [self statusOK:_api.delete_game(titleID.UTF8String)
                operation:@"Delete installed game" error:nullptr];
}

- (RPCS3GameCacheRecord*)gameCacheInfoForTitleID:(NSString*)titleID
{
    RPCS3GameCacheRecord* record = [[RPCS3GameCacheRecord alloc] init];
    if (!self.ready || !_api.get_game_cache_info || titleID.length == 0)
        return record;

    rpcs3_ios_game_cache_info info = {};
    info.struct_size = sizeof(info);
    if (_api.get_game_cache_info(titleID.UTF8String, &info) != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return record;
    }

    record.shaderBytes = info.shader;
    record.ppuBytes = info.ppu;
    record.spuBytes = info.spu;
    record.hdd1Bytes = info.hdd1;
    record.totalBytes = info.total;
    return record;
}

- (BOOL)clearGameCacheForTitleID:(NSString*)titleID
                            type:(uint32_t)type
                    bytesRemoved:(uint64_t*)bytesRemoved
{
    if (!self.ready || !_api.clear_game_cache || titleID.length == 0 ||
        type < RPCS3_IOS_GAME_CACHE_SHADER || type > RPCS3_IOS_GAME_CACHE_ALL)
        return NO;
    uint64_t removed = 0;
    const BOOL ok = [self statusOK:_api.clear_game_cache(
        titleID.UTF8String,
        static_cast<rpcs3_ios_game_cache_type>(type),
        &removed)
        operation:@"Clear game cache"
        error:nullptr];
    if (bytesRemoved) *bytesRemoved = removed;
    return ok;
}

- (NSArray<RPCS3GamePatchRecord*>*)installedGamePatchesForTitleID:(NSString*)titleID
{
    if (!self.ready || !_api.enumerate_game_patches || titleID.length == 0)
        return @[];
    NSMutableArray<RPCS3GamePatchRecord*>* records = [NSMutableArray array];
    const rpcs3_ios_status status = _api.enumerate_game_patches(
        titleID.UTF8String, &collect_game_patch, (__bridge void*)records);
    if (status != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return @[];
    }
    return [records copy];
}

- (NSString*)patchRepositoryURL
{
    if (!self.ready || !_api.get_patch_repository_url)
        return nil;
    char buffer[16384] = {};
    if (_api.get_patch_repository_url(buffer, sizeof(buffer)) != RPCS3_IOS_OK)
    {
        [self setFailure:[self coreError]];
        return nil;
    }
    return buffer[0] ? ([NSString stringWithUTF8String:buffer] ?: nil) : nil;
}

- (BOOL)installPatchRepositoryVersion:(NSString*)version
                               sha256:(NSString*)sha256
                                 data:(NSData*)data
{
    if (!self.ready || !_api.install_patch_repository ||
        version.length == 0 || sha256.length == 0 || data.length == 0)
        return NO;
    return [self statusOK:_api.install_patch_repository(
                version.UTF8String, sha256.UTF8String, data.bytes, data.length)
                operation:@"Patch repository installation" error:nullptr];
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
