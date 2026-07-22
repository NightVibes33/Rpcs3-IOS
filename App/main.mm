#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
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
static NSString *UTF8OrNone(const char *value) {
    return value ? ([NSString stringWithUTF8String:value] ?: @"invalid UTF-8") : @"none";
}

@interface MainViewController : UIViewController <UIDocumentPickerDelegate>
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
    status.text = @"Upstream-derived arm64 core archive with sandboxed ELF import and validation.";

    self.textView = [[UITextView alloc] init];
    self.textView.translatesAutoresizingMaskIntoConstraints = NO;
    self.textView.editable = NO;
    self.textView.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    self.textView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    self.textView.layer.cornerRadius = 12;
    self.textView.textContainerInset = UIEdgeInsetsMake(14, 14, 14, 14);

    UIButton *importELF = [UIButton buttonWithType:UIButtonTypeSystem];
    [importELF setTitle:@"Import ELF" forState:UIControlStateNormal];
    [importELF addTarget:self action:@selector(importELF) forControlEvents:UIControlEventTouchUpInside];

    UIButton *refresh = [UIButton buttonWithType:UIButtonTypeSystem];
    [refresh setTitle:@"Refresh Diagnostics" forState:UIControlStateNormal];
    [refresh addTarget:self action:@selector(refreshDiagnostics) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *actions = [[UIStackView alloc] initWithArrangedSubviews:@[importELF, refresh]];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.axis = UILayoutConstraintAxisHorizontal;
    actions.alignment = UIStackViewAlignmentCenter;
    actions.distribution = UIStackViewDistributionFillEqually;
    actions.spacing = 12;

    [self.view addSubview:status];
    [self.view addSubview:self.textView];
    [self.view addSubview:actions];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [status.topAnchor constraintEqualToAnchor:guide.topAnchor constant:16],
        [status.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [status.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [self.textView.topAnchor constraintEqualToAnchor:status.bottomAnchor constant:14],
        [self.textView.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [self.textView.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [actions.topAnchor constraintEqualToAnchor:self.textView.bottomAnchor constant:12],
        [actions.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:16],
        [actions.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [actions.bottomAnchor constraintEqualToAnchor:guide.bottomAnchor constant:-16]
    ]];
    [self refreshDiagnostics];
}

- (void)importELF {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSURL *source = urls.firstObject;
    if (!source) return;

    RPCS3IOSCoreDiagnostics core = rpcs3_ios_core_diagnostics();
    if (!core.data_path) {
        [self showError:@"The RPCS3 sandbox is not initialized."];
        return;
    }

    NSString *root = [NSString stringWithUTF8String:core.data_path];
    NSString *imports = [root stringByAppendingPathComponent:@"imports"];
    NSString *name = source.lastPathComponent.length ? source.lastPathComponent : @"boot.elf";
    NSString *uniqueName = [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name];
    NSURL *destination = [NSURL fileURLWithPath:[imports stringByAppendingPathComponent:uniqueName]];

    BOOL scoped = [source startAccessingSecurityScopedResource];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:imports
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    if (!error) {
        [[NSFileManager defaultManager] copyItemAtURL:source toURL:destination error:&error];
    }
    if (scoped) [source stopAccessingSecurityScopedResource];

    if (error) {
        [self showError:error.localizedDescription ?: @"Unable to import the selected file."];
        return;
    }

    rpcs3_ios_core_boot_elf(destination.path.fileSystemRepresentation);
    [self refreshDiagnostics];
}

- (void)showError:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Import failed"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)refreshDiagnostics {
    id<MTLDevice> gpu = MTLCreateSystemDefaultDevice();
    NSProcessInfo *process = NSProcessInfo.processInfo;
    UIDevice *device = UIDevice.currentDevice;
    RPCS3IOSCoreDiagnostics core = rpcs3_ios_core_diagnostics();

    self.textView.text = [NSString stringWithFormat:
        @"Build target: arm64 iPhoneOS 26.0+\n"
         "Core state: %d\n"
         "Platform initialized: %@\n"
         "Upstream RPCS3 crypto: %@\n"
         "PPU interpreter: %@\n"
         "SPU interpreter: %@\n"
         "JIT backend: %@\n"
         "Renderer backend: %@\n"
         "Sandbox data root: %@\n"
         "Last ELF SHA-256: %@\n"
         "Core message: %@\n\n"
         "Device model: %@\n"
         "System: %@ %@\n"
         "Processor count: %ld\n"
         "Physical memory: %@\n"
         "Low Power Mode: %@\n"
         "Thermal state: %ld\n"
         "Metal device: %@\n\n"
         "JIT probe: %@",
         core.state, YesNo(core.platform_initialized), YesNo(core.upstream_crypto_available),
         YesNo(core.ppu_interpreter_available), YesNo(core.spu_interpreter_available),
         YesNo(core.jit_available), YesNo(core.renderer_available),
         UTF8OrNone(core.data_path), UTF8OrNone(core.last_boot_sha256), UTF8OrNone(core.message),
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
