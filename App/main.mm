#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <sys/mman.h>
#import <sys/sysctl.h>
#import "RPCS3CoreBridge.h"

static NSString *ByteString(uint64_t value) {
    return [NSByteCountFormatter stringFromByteCount:(long long)value countStyle:NSByteCountFormatterCountStyleMemory];
}

static NSString *DeviceModel(void) {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) return @"unknown";
    char *machine = (char *)calloc(1, size);
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *result = [NSString stringWithUTF8String:machine] ?: @"unknown";
    free(machine);
    return result;
}

static NSString *JITProbe(void) {
#ifdef MAP_JIT
    size_t pageSize = (size_t)getpagesize();
    void *memory = mmap(NULL, pageSize, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON | MAP_JIT, -1, 0);
    if (memory == MAP_FAILED) return @"MAP_JIT allocation failed.";
    munmap(memory, pageSize);
    return @"MAP_JIT allocation succeeded; executable guest-code execution remains unverified.";
#else
    return @"MAP_JIT is not exposed by this SDK.";
#endif
}

static NSString *YesNo(int value) { return value ? @"yes" : @"no"; }

@interface MainViewController : UIViewController
@property(nonatomic, strong) UITextView *textView;
@end

@implementation MainViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.title = @"RPCS3 iOS Bring-Up";

    UILabel *status = [[UILabel alloc] init];
    status.translatesAutoresizingMaskIntoConstraints = NO;
    status.numberOfLines = 0;
    status.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    status.text = @"Real-device iOS 26 shell with sandbox storage and a replaceable RPCS3 core bridge.";

    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.textView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.textView.layer.cornerRadius = 12;
    self.textView.textContainerInset = UIEdgeInsetsMake(14, 14, 14, 14);

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    refresh.translatesAutoresizingMaskIntoConstraints = NO;
    [refresh setTitle:@"Refresh Diagnostics" forState:UIControlStateNormal];
    [refresh addTarget:self action:@selector(refreshDiagnostics) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:status];
    [self.view addSubview:self.textView];
    [self.view addSubview:refresh];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [status.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [status.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [status.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [self.textView.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:14],
        [self.textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [self.textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [refresh.topAnchor constraintEqualToAnchor:self.textView.bottomAnchor constant:12],
        [refresh.centerXAnchor constraintEqualToAnchor:guide.centerXAnchor],
        [refresh.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16]
    ]];
    [self refreshDiagnostics];
}

- (void)refreshDiagnostics {
    id<MTLDevice> gpu = MTLCreateSystemDefaultDevice();
    NSProcessInfo *process = NSProcessInfo.processInfo;
    UIDevice *device = UIDevice.currentDevice;
    RPCS3IOSCoreDiagnostics core = rpcs3_ios_core_diagnostics();
    NSString *coreMessage = core.message ? [NSString stringWithUTF8String:core.message] : @"none";
    NSString *dataPath = core.data_path ? [NSString stringWithUTF8String:core.data_path] : @"not initialized";

    self.textView.text = [NSString stringWithFormat:
        @"Build target: arm64 iPhoneOS 26.0+\n"
         "Core state: %d\n"
         "Platform initialized: %@\n"
         "PPU interpreter: %@\n"
         "SPU interpreter: %@\n"
         "JIT backend: %@\n"
         "Renderer backend: %@\n"
         "Sandbox data root: %@\n"
         "Core message: %@\n\n"
         "Device model: %@\n"
         "System: %@ %@\n"
         "Processor count: %ld\n"
         "Physical memory: %@\n"
         "Low Power Mode: %@\n"
         "Thermal state: %ld\n"
         "Metal device: %@\n\n"
         "JIT probe: %@",
         core.state, YesNo(core.platform_initialized),
         YesNo(core.ppu_interpreter_available), YesNo(core.spu_interpreter_available),
         YesNo(core.jit_available), YesNo(core.renderer_available), dataPath, coreMessage,
         DeviceModel(), device.systemName, device.systemVersion,
         (long)process.processorCount, ByteString(process.physicalMemory),
         process.lowPowerModeEnabled ? @"enabled" : @"disabled",
         (long)process.thermalState, gpu.name ?: @"unavailable", JITProbe()];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application; (void)launchOptions;
    rpcs3_ios_core_initialize(nullptr);
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:[[MainViewController alloc] init]];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
