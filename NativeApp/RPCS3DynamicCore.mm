#import "RPCS3DynamicCore.h"
#include "RPCS3IOS.h"

#import <dlfcn.h>
#import <os/log.h>

#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <string>

static NSString * const RPCS3DynamicCoreErrorDomain = @"com.nightvibes33.rpcs3.dynamiccore";

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
    decltype(&rpcs3_ios_install_iso) install_iso = nullptr;
    decltype(&rpcs3_ios_install_zip) install_zip = nullptr;
    decltype(&rpcs3_ios_set_display_surface) set_display_surface = nullptr;
    decltype(&rpcs3_ios_set_pad_state) set_pad_state = nullptr;
    decltype(&rpcs3_ios_boot_big_picture_mode) boot_big_picture_mode = nullptr;
    decltype(&rpcs3_ios_get_emulation_state) get_emulation_state = nullptr;
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

NSError* make_error(NSInteger code, NSString* message)
{
    return [NSError errorWithDomain:RPCS3DynamicCoreErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"RPCS3Core operation failed"}];
}
}

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
    LOAD_API(rpcs3_ios_install_iso, install_iso);
    LOAD_API(rpcs3_ios_install_zip, install_zip);
    LOAD_API(rpcs3_ios_set_display_surface, set_display_surface);
    LOAD_API(rpcs3_ios_set_pad_state, set_pad_state);
    LOAD_API(rpcs3_ios_boot_big_picture_mode, boot_big_picture_mode);
    LOAD_API(rpcs3_ios_get_emulation_state, get_emulation_state);
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

- (BOOL)setPlayerOneConnected:(BOOL)connected
                      buttons:(uint64_t)buttons
                        leftX:(float)leftX
                        leftY:(float)leftY
                       rightX:(float)rightX
                       rightY:(float)rightY
                  leftTrigger:(float)leftTrigger
                 rightTrigger:(float)rightTrigger
{
    if (!self.ready || !_api.set_pad_state)
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
    return _api.set_pad_state(0, &state) == RPCS3_IOS_OK;
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

- (BOOL)installContentAtPath:(NSString*)path
{
    NSString* ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"pup"])
        return [self installFirmwareAtPath:path error:nullptr];
    if ([ext isEqualToString:@"pkg"])
        return [self installPackageAtPath:path error:nullptr];
    if ([ext isEqualToString:@"iso"])
        return [self installISOAtPath:path error:nullptr];
    if ([ext isEqualToString:@"zip"])
        return [self installZIPAtPath:path error:nullptr];

    [self setFailure:[NSString stringWithFormat:@"Unsupported RPCS3 content type: .%@", ext]];
    return NO;
}

- (BOOL)pause { return [self pauseWithError:nullptr]; }
- (BOOL)resume { return [self resumeWithError:nullptr]; }
- (BOOL)stop { return [self stopWithError:nullptr]; }
- (BOOL)shutdown { return [self shutdownWithError:nullptr]; }



@end
