#import "RPCS3AppleMobilePlatform.h"

#import <AVFoundation/AVFoundation.h>
#import <Foundation/Foundation.h>
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#import <UIKit/UIKit.h>
#import <os/log.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <mutex>
#include <string>

extern "C" int rpcs3_ios_upstream_set_pad_state(
    unsigned int buttons,
    unsigned char left_x,
    unsigned char left_y,
    unsigned char right_x,
    unsigned char right_y) __attribute__((weak_import));
extern "C" int rpcs3_ios_upstream_pause(void) __attribute__((weak_import));
extern "C" int rpcs3_ios_upstream_resume(void) __attribute__((weak_import));
extern "C" int rpcs3_ios_upstream_state(void) __attribute__((weak_import));

namespace
{
std::atomic_bool g_initialized{false};
std::atomic_bool g_emulation_active{false};
std::atomic_bool g_auto_paused{false};
std::atomic_bool g_first_frame_logged{false};
std::mutex g_path_mutex;
std::string g_application_support_path;
std::string g_documents_path;
CADisplayLink* g_controller_display_link = nil;
NSMutableArray<id>* g_observer_tokens = nil;
os_log_t g_log = nil;

constexpr int kUpstreamRunningState = 2;

unsigned char axis_to_byte(float value, bool invert)
{
    const float clamped = std::clamp(value, -1.0f, 1.0f);
    const float directed = invert ? -clamped : clamped;
    return static_cast<unsigned char>(std::lround(128.0f + directed * 127.0f));
}

void ensure_paths()
{
    std::lock_guard lock(g_path_mutex);
    if (!g_application_support_path.empty())
    {
        return;
    }

    NSFileManager* manager = NSFileManager.defaultManager;
    NSURL* support = [manager URLForDirectory:NSApplicationSupportDirectory
                                      inDomain:NSUserDomainMask
                             appropriateForURL:nil
                                        create:YES
                                         error:nil];
    support = [support URLByAppendingPathComponent:@"RPCS3" isDirectory:YES];
    [manager createDirectoryAtURL:support withIntermediateDirectories:YES attributes:nil error:nil];

    NSURL* documents = [manager URLForDirectory:NSDocumentDirectory
                                        inDomain:NSUserDomainMask
                               appropriateForURL:nil
                                          create:YES
                                           error:nil];

    g_application_support_path = support.fileSystemRepresentation ?: "";
    g_documents_path = documents.fileSystemRepresentation ?: "";
}

void write_checkpoint(NSString* name, NSString* detail)
{
    ensure_paths();
    if (g_application_support_path.empty())
    {
        return;
    }

    NSString* directory = [NSString stringWithUTF8String:g_application_support_path.c_str()];
    directory = [directory stringByAppendingPathComponent:@"runtime"];
    [NSFileManager.defaultManager createDirectoryAtPath:directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    NSString* path = [directory stringByAppendingPathComponent:@"apple-mobile-runtime.jsonl"];
    NSDictionary* record = @{
        @"timestamp": @([[NSDate date] timeIntervalSince1970]),
        @"checkpoint": name ?: @"unknown",
        @"detail": detail ?: @"",
        @"idiom": UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad ? @"iPadOS" : @"iOS",
        @"thermalState": @(NSProcessInfo.processInfo.thermalState),
        @"memory": @(NSProcessInfo.processInfo.physicalMemory),
    };

    NSData* data = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    if (!data)
    {
        return;
    }

    NSMutableData* line = [data mutableCopy];
    const uint8_t newline = '\n';
    [line appendBytes:&newline length:1];

    if (![NSFileManager.defaultManager fileExistsAtPath:path])
    {
        [line writeToFile:path atomically:YES];
        return;
    }

    NSFileHandle* handle = [NSFileHandle fileHandleForWritingAtPath:path];
    @try
    {
        [handle seekToEndOfFile];
        [handle writeData:line];
        [handle closeFile];
    }
    @catch (__unused NSException* exception)
    {
        [handle closeFile];
    }
}

uint32_t controller_buttons(GCExtendedGamepad* pad)
{
    uint32_t buttons = 0;
    if (pad.dpad.up.isPressed) buttons |= RPCS3AppleMobilePadUp;
    if (pad.dpad.down.isPressed) buttons |= RPCS3AppleMobilePadDown;
    if (pad.dpad.left.isPressed) buttons |= RPCS3AppleMobilePadLeft;
    if (pad.dpad.right.isPressed) buttons |= RPCS3AppleMobilePadRight;

    // Apple A/B/X/Y placement maps naturally to PS3 Cross/Circle/Square/Triangle.
    if (pad.buttonA.isPressed) buttons |= RPCS3AppleMobilePadCross;
    if (pad.buttonB.isPressed) buttons |= RPCS3AppleMobilePadCircle;
    if (pad.buttonX.isPressed) buttons |= RPCS3AppleMobilePadSquare;
    if (pad.buttonY.isPressed) buttons |= RPCS3AppleMobilePadTriangle;
    if (pad.leftShoulder.isPressed) buttons |= RPCS3AppleMobilePadL1;
    if (pad.rightShoulder.isPressed) buttons |= RPCS3AppleMobilePadR1;
    if (pad.leftTrigger.value > 0.20f) buttons |= RPCS3AppleMobilePadL2;
    if (pad.rightTrigger.value > 0.20f) buttons |= RPCS3AppleMobilePadR2;

    if (@available(iOS 12.1, *))
    {
        if (pad.leftThumbstickButton.isPressed) buttons |= RPCS3AppleMobilePadL3;
        if (pad.rightThumbstickButton.isPressed) buttons |= RPCS3AppleMobilePadR3;
    }
    if (@available(iOS 13.0, *))
    {
        if (pad.buttonMenu.isPressed) buttons |= RPCS3AppleMobilePadStart;
        if (pad.buttonOptions && pad.buttonOptions.isPressed) buttons |= RPCS3AppleMobilePadSelect;
        if (pad.buttonHome && pad.buttonHome.isPressed) buttons |= RPCS3AppleMobilePadPS;
    }
    return buttons;
}

@interface RPCS3AppleMobileControllerPump : NSObject
+ (instancetype)shared;
- (void)tick:(CADisplayLink*)link;
@end

@implementation RPCS3AppleMobileControllerPump
+ (instancetype)shared
{
    static RPCS3AppleMobileControllerPump* instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [RPCS3AppleMobileControllerPump new]; });
    return instance;
}

- (void)tick:(__unused CADisplayLink*)link
{
    if (!g_emulation_active.load(std::memory_order_relaxed) || !rpcs3_ios_upstream_set_pad_state)
    {
        return;
    }

    GCController* controller = GCController.controllers.firstObject;
    GCExtendedGamepad* pad = controller.extendedGamepad;
    if (!pad)
    {
        // Do not emit a neutral state without a native controller because the
        // existing Qt touch overlay owns the same upstream pad bridge.
        return;
    }

    const uint32_t buttons = controller_buttons(pad);
    rpcs3_ios_upstream_set_pad_state(
        buttons,
        axis_to_byte(pad.leftThumbstick.xAxis.value, false),
        axis_to_byte(pad.leftThumbstick.yAxis.value, true),
        axis_to_byte(pad.rightThumbstick.xAxis.value, false),
        axis_to_byte(pad.rightThumbstick.yAxis.value, true));
}
@end

void set_idle_timer(bool display_sleep_enabled)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplication.sharedApplication.idleTimerDisabled = !display_sleep_enabled;
    });
}

void pause_for_background()
{
    if (!g_emulation_active.load(std::memory_order_relaxed))
    {
        return;
    }

    if (rpcs3_ios_upstream_state && rpcs3_ios_upstream_pause &&
        rpcs3_ios_upstream_state() == kUpstreamRunningState && rpcs3_ios_upstream_pause() != 0)
    {
        g_auto_paused.store(true, std::memory_order_relaxed);
        write_checkpoint(@"lifecycle.pause", @"Paused RPCS3 before entering the background");
    }
}

void resume_from_background()
{
    if (g_auto_paused.exchange(false, std::memory_order_relaxed) && rpcs3_ios_upstream_resume)
    {
        rpcs3_ios_upstream_resume();
        write_checkpoint(@"lifecycle.resume", @"Resumed RPCS3 after returning active");
    }
}

void install_observers()
{
    NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
    g_observer_tokens = [NSMutableArray array];

    [g_observer_tokens addObject:[center addObserverForName:UIApplicationDidEnterBackgroundNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification* note) {
        pause_for_background();
        [AVAudioSession.sharedInstance setActive:NO
                                    withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                          error:nil];
    }]];

    [g_observer_tokens addObject:[center addObserverForName:UIApplicationDidBecomeActiveNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification* note) {
        rpcs3_apple_mobile_configure_audio_session();
        resume_from_background();
    }]];

    [g_observer_tokens addObject:[center addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification* note) {
        write_checkpoint(@"memory.warning", @"UIKit delivered a memory warning");
    }]];

    [g_observer_tokens addObject:[center addObserverForName:NSProcessInfoThermalStateDidChangeNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification* note) {
        const NSProcessInfoThermalState state = NSProcessInfo.processInfo.thermalState;
        write_checkpoint(@"thermal.change", [NSString stringWithFormat:@"state=%ld", (long)state]);
        if (state == NSProcessInfoThermalStateCritical)
        {
            pause_for_background();
        }
    }]];

    [g_observer_tokens addObject:[center addObserverForName:GCControllerDidConnectNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification* note) {
        write_checkpoint(@"controller.connected", @"GameController device connected");
    }]];

    [g_observer_tokens addObject:[center addObserverForName:GCControllerDidDisconnectNotification
                                                        object:nil
                                                         queue:NSOperationQueue.mainQueue
                                                    usingBlock:^(__unused NSNotification* note) {
        if (rpcs3_ios_upstream_set_pad_state)
        {
            rpcs3_ios_upstream_set_pad_state(0, 128, 128, 128, 128);
        }
        write_checkpoint(@"controller.disconnected", @"GameController device disconnected");
    }]];
}
} // namespace

extern "C" void rpcs3_apple_mobile_initialize(void)
{
    if (g_initialized.exchange(true, std::memory_order_acq_rel))
    {
        return;
    }

    ensure_paths();
    g_log = os_log_create("com.nightvibes33.rpcs3ios", "AppleMobile");

    dispatch_async(dispatch_get_main_queue(), ^{
        install_observers();
        rpcs3_apple_mobile_configure_audio_session();

        UIScreen* screen = UIScreen.mainScreen;
        g_controller_display_link = [screen displayLinkWithTarget:RPCS3AppleMobileControllerPump.shared
                                                         selector:@selector(tick:)];
        g_controller_display_link.preferredFramesPerSecond = std::max(60, (int)screen.maximumFramesPerSecond);
        [g_controller_display_link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

        write_checkpoint(@"platform.initialize", UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad
            ? @"Initialized shared iPadOS platform layer"
            : @"Initialized shared iOS platform layer");
    });
}

extern "C" void rpcs3_apple_mobile_shutdown(void)
{
    if (!g_initialized.exchange(false, std::memory_order_acq_rel))
    {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [g_controller_display_link invalidate];
        g_controller_display_link = nil;
        for (id token in g_observer_tokens)
        {
            [NSNotificationCenter.defaultCenter removeObserver:token];
        }
        g_observer_tokens = nil;
        UIApplication.sharedApplication.idleTimerDisabled = NO;
    });
}

extern "C" RPCS3AppleMobileDeviceProfile rpcs3_apple_mobile_device_profile(void)
{
    NSProcessInfo* info = NSProcessInfo.processInfo;
    UIScreen* screen = UIScreen.mainScreen;
    const bool ipad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
    const uint64_t physical = info.physicalMemory;
    const uint64_t reserve = ipad ? (768ull << 20) : (1024ull << 20);
    const uint64_t recommended = physical > reserve ? physical - reserve : physical / 2;

    RPCS3AppleMobileDeviceProfile profile{};
    profile.is_ipad = ipad ? 1 : 0;
    if (@available(iOS 16.1, *))
    {
        profile.supports_hover = ipad ? 1 : 0;
    }
    else
    {
        profile.supports_hover = 0;
    }
    profile.supports_pencil = ipad ? 1 : 0;
    profile.maximum_frames_per_second = (int)screen.maximumFramesPerSecond;
    profile.active_processor_count = (int)info.activeProcessorCount;
    profile.physical_memory_bytes = physical;
    profile.recommended_guest_memory_bytes = recommended;
    return profile;
}

extern "C" const char* rpcs3_apple_mobile_application_support_path(void)
{
    ensure_paths();
    return g_application_support_path.c_str();
}

extern "C" const char* rpcs3_apple_mobile_documents_path(void)
{
    ensure_paths();
    return g_documents_path.c_str();
}

extern "C" void rpcs3_apple_mobile_set_display_sleep_enabled(int enabled)
{
    set_idle_timer(enabled != 0);
}

extern "C" void rpcs3_apple_mobile_set_emulation_active(int active)
{
    const bool running = active != 0;
    g_emulation_active.store(running, std::memory_order_relaxed);
    set_idle_timer(!running);
    if (running)
    {
        rpcs3_apple_mobile_configure_audio_session();
        write_checkpoint(@"emulation.active", @"Emulation marked active");
    }
    else
    {
        if (rpcs3_ios_upstream_set_pad_state)
        {
            rpcs3_ios_upstream_set_pad_state(0, 128, 128, 128, 128);
        }
        write_checkpoint(@"emulation.inactive", @"Emulation marked inactive");
    }
}

extern "C" int rpcs3_apple_mobile_configure_audio_session(void)
{
    __block BOOL success = YES;
    void (^configure)(void) = ^{
        AVAudioSession* session = AVAudioSession.sharedInstance;
        NSError* error = nil;
        success = [session setCategory:AVAudioSessionCategoryPlayback
                                  mode:AVAudioSessionModeDefault
                               options:0
                                 error:&error];
        success = [session setPreferredSampleRate:48000.0 error:&error] && success;
        success = [session setPreferredIOBufferDuration:(256.0 / 48000.0) error:&error] && success;
        success = [session setActive:YES error:&error] && success;
        if (!success)
        {
            os_log_error(g_log ?: OS_LOG_DEFAULT, "AVAudioSession setup failed: %{public}@", error.localizedDescription);
            write_checkpoint(@"audio.failure", error.localizedDescription ?: @"unknown AVAudioSession error");
        }
        else
        {
            write_checkpoint(@"audio.ready", @"48 kHz playback session active");
        }
    };

    if (NSThread.isMainThread)
    {
        configure();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), configure);
    }
    return success ? 1 : 0;
}

extern "C" void rpcs3_apple_mobile_log_checkpoint(const char* name, const char* detail)
{
    NSString* ns_name = name ? [NSString stringWithUTF8String:name] : @"unknown";
    NSString* ns_detail = detail ? [NSString stringWithUTF8String:detail] : @"";
    write_checkpoint(ns_name, ns_detail);
}

extern "C" void rpcs3_apple_mobile_mark_frame_presented(void)
{
    if (!g_first_frame_logged.exchange(true, std::memory_order_acq_rel))
    {
        write_checkpoint(@"graphics.first-frame", @"Vulkan/MoltenVK completed its first presentation path");
    }
}

__attribute__((constructor)) static void rpcs3_apple_mobile_constructor(void)
{
    rpcs3_apple_mobile_initialize();
}
