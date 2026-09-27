#import <UIKit/UIKit.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#include "RPCS3IOS.h"

#include <algorithm>
#include <cmath>
#include <string>

@interface RPCS3MetalView : UIView
@end

@implementation RPCS3MetalView
+ (Class)layerClass
{
    return CAMetalLayer.class;
}
@end

static void RPCS3Log(void*, int32_t level, const char* message)
{
    if (!message) return;
    NSLog(@"[RPCS3:%d] %s", level, message);
}

static void RPCS3RunOnMain(void*, rpcs3_ios_main_thread_task task, void* taskContext)
{
    if (!task) return;
    if (NSThread.isMainThread)
    {
        task(taskContext);
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        task(taskContext);
    });
}

@interface RPCS3ViewController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) UIVisualEffectView* panel;
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UIButton* startButton;
@property(nonatomic, strong) UIButton* importButton;
@property(nonatomic, strong) CADisplayLink* inputLink;
@property(nonatomic, assign) BOOL coreReady;
@property(nonatomic, assign) BOOL surfaceAttached;
@property(nonatomic, assign) BOOL emulationStarted;
@end

@implementation RPCS3ViewController
{
    std::string _supportPath;
    std::string _cachePath;
}

- (void)loadView
{
    RPCS3MetalView* view = [[RPCS3MetalView alloc] initWithFrame:UIScreen.mainScreen.bounds];
    view.backgroundColor = UIColor.blackColor;

    CAMetalLayer* layer = (CAMetalLayer*)view.layer;
    layer.device = MTLCreateSystemDefaultDevice();
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    layer.framebufferOnly = NO;
    layer.contentsScale = UIScreen.mainScreen.scale;

    self.view = view;

    UIBlurEffect* blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark];
    self.panel = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.panel.translatesAutoresizingMaskIntoConstraints = NO;
    self.panel.layer.cornerRadius = 22.0;
    self.panel.clipsToBounds = YES;
    [view addSubview:self.panel];

    UILabel* title = [[UILabel alloc] init];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.text = @"RPCS3";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    title.textAlignment = NSTextAlignmentCenter;

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.text = @"Initializing RPCS3Core…";
    self.statusLabel.textColor = UIColor.secondaryLabelColor;
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];

    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.startButton setTitle:@"Start RPCS3" forState:UIControlStateNormal];
    self.startButton.titleLabel.font = [UIFont systemFontOfSize:19 weight:UIFontWeightSemibold];
    self.startButton.enabled = NO;
    [self.startButton addTarget:self action:@selector(startRPCS3) forControlEvents:UIControlEventTouchUpInside];

    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.importButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.importButton setTitle:@"Install Firmware / Content" forState:UIControlStateNormal];
    self.importButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.importButton.enabled = NO;
    [self.importButton addTarget:self action:@selector(importContent) forControlEvents:UIControlEventTouchUpInside];

    UIStackView* stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        title, self.statusLabel, self.startButton, self.importButton
    ]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 18.0;
    stack.alignment = UIStackViewAlignmentFill;
    [self.panel.contentView addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [self.panel.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [self.panel.centerYAnchor constraintEqualToAnchor:view.centerYAnchor],
        [self.panel.widthAnchor constraintLessThanOrEqualToConstant:520],
        [self.panel.widthAnchor constraintEqualToAnchor:view.widthAnchor multiplier:0.72],

        [stack.topAnchor constraintEqualToAnchor:self.panel.contentView.topAnchor constant:28],
        [stack.bottomAnchor constraintEqualToAnchor:self.panel.contentView.bottomAnchor constant:-28],
        [stack.leadingAnchor constraintEqualToAnchor:self.panel.contentView.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:self.panel.contentView.trailingAnchor constant:-28],
        [self.startButton.heightAnchor constraintEqualToConstant:52],
        [self.importButton.heightAnchor constraintEqualToConstant:44],
    ]];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationWillResignActive)
                                                 name:UIApplicationWillResignActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerChanged)
                                                 name:GCControllerDidConnectNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(controllerChanged)
                                                 name:GCControllerDidDisconnectNotification
                                               object:nil];

    self.inputLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(pushControllerState)];
    [self.inputLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        [self initializeCore];
    });
}

- (void)viewDidLayoutSubviews
{
    [super viewDidLayoutSubviews];
    CAMetalLayer* layer = (CAMetalLayer*)self.view.layer;
    CGFloat scale = self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    layer.contentsScale = scale;
    CGSize size = self.view.bounds.size;
    layer.drawableSize = CGSizeMake(std::max<CGFloat>(1.0, size.width * scale),
                                    std::max<CGFloat>(1.0, size.height * scale));
    if (self.surfaceAttached && !self.emulationStarted)
    {
        [self attachSurface];
    }
}

- (void)setStatus:(NSString*)status
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = status;
    });
}

- (void)initializeCore
{
    @autoreleasepool
    {
        NSFileManager* fm = NSFileManager.defaultManager;
        NSURL* supportBase = [fm URLsForDirectory:NSApplicationSupportDirectory
                                         inDomains:NSUserDomainMask].firstObject;
        NSURL* cacheBase = [fm URLsForDirectory:NSCachesDirectory
                                       inDomains:NSUserDomainMask].firstObject;
        NSURL* support = [supportBase URLByAppendingPathComponent:@"RPCS3" isDirectory:YES];
        NSURL* cache = [cacheBase URLByAppendingPathComponent:@"RPCS3" isDirectory:YES];

        NSError* error = nil;
        [fm createDirectoryAtURL:support withIntermediateDirectories:YES attributes:nil error:&error];
        if (error)
        {
            [self setStatus:[NSString stringWithFormat:@"Storage setup failed: %@", error.localizedDescription]];
            return;
        }
        error = nil;
        [fm createDirectoryAtURL:cache withIntermediateDirectories:YES attributes:nil error:&error];
        if (error)
        {
            [self setStatus:[NSString stringWithFormat:@"Cache setup failed: %@", error.localizedDescription]];
            return;
        }

        _supportPath = support.fileSystemRepresentation ?: "";
        _cachePath = cache.fileSystemRepresentation ?: "";

        AVAudioSession* session = AVAudioSession.sharedInstance;
        [session setCategory:AVAudioSessionCategoryPlayback error:nil];
        [session setPreferredSampleRate:48000.0 error:nil];
        [session setPreferredIOBufferDuration:(512.0 / 48000.0) error:nil];
        [session setActive:YES error:nil];

        if (rpcs3_ios_abi_version() != RPCS3_IOS_ABI_VERSION)
        {
            [self setStatus:[NSString stringWithFormat:@"RPCS3Core ABI mismatch: core %u, host %u",
                             rpcs3_ios_abi_version(), RPCS3_IOS_ABI_VERSION]];
            return;
        }

        rpcs3_ios_config config = {};
        config.abi_version = RPCS3_IOS_ABI_VERSION;
        config.struct_size = sizeof(config);
        config.application_support_path = _supportPath.c_str();
        config.cache_path = _cachePath.c_str();
        config.log_callback = &RPCS3Log;
        config.main_thread_callback = &RPCS3RunOnMain;
        config.user_context = (__bridge void*)self;
        config.expanded_jit_arena = 1024;
        config.reserved = 0;

        const rpcs3_ios_status status = rpcs3_ios_initialize(&config);
        if (status != RPCS3_IOS_OK)
        {
            const char* last = rpcs3_ios_last_error();
            NSString* message = last ? [NSString stringWithUTF8String:last] : @"unknown initialization failure";
            [self setStatus:[NSString stringWithFormat:@"RPCS3Core init failed (%d): %@", status, message]];
            return;
        }

        uint64_t output = 0;
        const rpcs3_ios_status jitStatus = rpcs3_ios_run_llvm_self_test(11, &output);
        if (jitStatus != RPCS3_IOS_OK || output != 40)
        {
            const char* last = rpcs3_ios_last_error();
            NSString* message = last ? [NSString stringWithUTF8String:last] : @"JIT unavailable";
            [self setStatus:[NSString stringWithFormat:
                @"LLVM/JIT is not executable. Launch RPCS3 through StikDebug and try again. (%@)", message]];
            return;
        }

        self.coreReady = YES;
        NSString* firmware = nil;
        if (const char* version = rpcs3_ios_firmware_version(); version && *version)
            firmware = [NSString stringWithUTF8String:version];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.startButton.enabled = YES;
            self.importButton.enabled = YES;
            self.statusLabel.text = firmware.length
                ? [NSString stringWithFormat:@"RPCS3Core ABI %u ready • Firmware %@", RPCS3_IOS_ABI_VERSION, firmware]
                : [NSString stringWithFormat:@"RPCS3Core ABI %u ready • Install PS3 firmware if needed", RPCS3_IOS_ABI_VERSION];
        });
    }
}

- (BOOL)attachSurface
{
    if (!self.coreReady) return NO;

    CAMetalLayer* layer = (CAMetalLayer*)self.view.layer;
    CGFloat scale = self.view.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGSize logical = self.view.bounds.size;
    CGSize drawable = CGSizeMake(std::max<CGFloat>(1.0, logical.width * scale),
                                 std::max<CGFloat>(1.0, logical.height * scale));
    layer.drawableSize = drawable;

    rpcs3_ios_display_surface surface = {};
    surface.struct_size = sizeof(surface);
    surface.width = (uint32_t)llround(drawable.width);
    surface.height = (uint32_t)llround(drawable.height);
    surface.refresh_rate = (float)std::max<NSInteger>(20, UIScreen.mainScreen.maximumFramesPerSecond);
    surface.metal_layer = (__bridge void*)layer;

    const rpcs3_ios_status status = rpcs3_ios_set_display_surface(&surface);
    self.surfaceAttached = status == RPCS3_IOS_OK;
    if (!self.surfaceAttached)
    {
        const char* last = rpcs3_ios_last_error();
        NSString* message = last ? [NSString stringWithUTF8String:last] : @"unknown display error";
        [self setStatus:[NSString stringWithFormat:@"CAMetalLayer attach failed (%d): %@", status, message]];
    }
    return self.surfaceAttached;
}

- (void)startRPCS3
{
    if (!self.coreReady || self.emulationStarted) return;
    if (![self attachSurface]) return;

    self.startButton.enabled = NO;
    self.importButton.enabled = NO;
    [self setStatus:@"Starting RPCS3 Big Picture…"];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const rpcs3_ios_status status = rpcs3_ios_boot_big_picture_mode();
        if (status != RPCS3_IOS_OK)
        {
            const char* last = rpcs3_ios_last_error();
            NSString* message = last ? [NSString stringWithUTF8String:last] : @"unknown boot failure";
            dispatch_async(dispatch_get_main_queue(), ^{
                self.startButton.enabled = YES;
                self.importButton.enabled = YES;
                self.statusLabel.text = [NSString stringWithFormat:@"Big Picture boot failed (%d): %@", status, message];
            });
            return;
        }

        self.emulationStarted = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.panel.hidden = YES;
        });
    });
}

- (void)importContent
{
    NSArray<UTType*>* types = @[UTTypeData, UTTypeArchive, UTTypeDiskImage];
    UIDocumentPickerViewController* picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController*)controller
didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
    NSURL* source = urls.firstObject;
    if (!source) return;

    self.startButton.enabled = NO;
    self.importButton.enabled = NO;
    [self setStatus:[NSString stringWithFormat:@"Installing %@…", source.lastPathComponent]];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL scoped = [source startAccessingSecurityScopedResource];
        NSString* ext = source.pathExtension.lowercaseString;
        rpcs3_ios_status status = RPCS3_IOS_INVALID_ARGUMENT;

        if ([ext isEqualToString:@"pup"])
        {
            status = rpcs3_ios_install_firmware(source.fileSystemRepresentation, nullptr, nullptr);
        }
        else if ([ext isEqualToString:@"pkg"])
        {
            status = rpcs3_ios_install_package(source.fileSystemRepresentation, nullptr, nullptr);
        }
        else if ([ext isEqualToString:@"iso"])
        {
            status = rpcs3_ios_install_iso(source.fileSystemRepresentation, nullptr, nullptr, nullptr);
        }
        else if ([ext isEqualToString:@"zip"])
        {
            status = rpcs3_ios_install_zip(source.fileSystemRepresentation, nullptr, nullptr);
        }

        if (scoped) [source stopAccessingSecurityScopedResource];

        const char* last = status == RPCS3_IOS_OK ? nullptr : rpcs3_ios_last_error();
        NSString* error = last ? [NSString stringWithUTF8String:last] : @"unsupported content or unknown error";

        dispatch_async(dispatch_get_main_queue(), ^{
            self.startButton.enabled = YES;
            self.importButton.enabled = YES;
            self.statusLabel.text = status == RPCS3_IOS_OK
                ? [NSString stringWithFormat:@"%@ installed by RPCS3Core.", source.lastPathComponent]
                : [NSString stringWithFormat:@"Install failed (%d): %@", status, error];
        });
    });
}

- (void)controllerChanged
{
    [self pushControllerState];
}

static float AxisValue(GCControllerAxisInput* axis)
{
    return axis ? std::clamp(axis.value, -1.0f, 1.0f) : 0.0f;
}

- (void)pushControllerState
{
    if (!self.coreReady) return;

    GCController* controller = GCController.controllers.firstObject;
    GCExtendedGamepad* pad = controller.extendedGamepad;
    rpcs3_ios_pad_state state = {};
    state.struct_size = sizeof(state);
    state.connected = pad ? 1u : 0u;

    if (pad)
    {
        uint64_t buttons = 0;
        if (pad.dpad.up.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_UP;
        if (pad.dpad.down.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_DOWN;
        if (pad.dpad.left.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_LEFT;
        if (pad.dpad.right.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_DPAD_RIGHT;
        if (pad.buttonA.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_CROSS;
        if (pad.buttonB.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_CIRCLE;
        if (pad.buttonX.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_SQUARE;
        if (pad.buttonY.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_TRIANGLE;
        if (pad.leftShoulder.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_L1;
        if (pad.rightShoulder.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_R1;
        if (pad.leftTrigger.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_L2;
        if (pad.rightTrigger.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_R2;
        if (pad.leftThumbstickButton.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_L3;
        if (pad.rightThumbstickButton.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_R3;
        if (pad.buttonMenu.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_START;
        if (pad.buttonOptions.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_SELECT;
        if (@available(iOS 14.0, *))
        {
            if (pad.buttonHome && pad.buttonHome.isPressed) buttons |= RPCS3_IOS_PAD_BUTTON_PS;
        }

        state.buttons = buttons;
        state.left_stick_x = AxisValue(pad.leftThumbstick.xAxis);
        state.left_stick_y = AxisValue(pad.leftThumbstick.yAxis);
        state.right_stick_x = AxisValue(pad.rightThumbstick.xAxis);
        state.right_stick_y = AxisValue(pad.rightThumbstick.yAxis);
        state.left_trigger = std::clamp(pad.leftTrigger.value, 0.0f, 1.0f);
        state.right_trigger = std::clamp(pad.rightTrigger.value, 0.0f, 1.0f);
    }

    rpcs3_ios_set_pad_state(0, &state);
}

- (void)applicationWillResignActive
{
    if (self.emulationStarted)
        rpcs3_ios_pause_emulation();
}

- (void)applicationDidBecomeActive
{
    if (self.emulationStarted)
        rpcs3_ios_resume_emulation();
}

- (void)dealloc
{
    [self.inputLink invalidate];
    if (self.emulationStarted)
        rpcs3_ios_stop_emulation();
    if (self.surfaceAttached)
        rpcs3_ios_set_display_surface(nullptr);
    if (self.coreReady)
        rpcs3_ios_shutdown();
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskLandscape;
}
@end

@interface RPCS3AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end

@implementation RPCS3AppDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    (void)application;
    (void)launchOptions;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[RPCS3ViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char* argv[])
{
    @autoreleasepool
    {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(RPCS3AppDelegate.class));
    }
}
