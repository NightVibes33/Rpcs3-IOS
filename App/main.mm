#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "RPCS3CoreBridge.h"

static NSString *RPCS3Root(void) {
    RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics();
    return d.data_path ? ([NSString stringWithUTF8String:d.data_path] ?: @"") : @"";
}

@interface RPCS3LibraryController : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic, strong) NSArray<NSURL *> *items;
@end

@implementation RPCS3LibraryController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Games";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importGame)];
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"game"];
    [self reloadItems];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadItems]; }
- (NSString *)importsPath { return [RPCS3Root() stringByAppendingPathComponent:@"imports"]; }
- (void)reloadItems {
    NSArray *items = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:self.importsPath] includingPropertiesForKeys:@[NSURLFileSizeKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
    self.items = [items sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) { return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent]; }];
    [self.tableView reloadData];
}
- (void)importGame {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    [[NSFileManager defaultManager] createDirectoryAtPath:self.importsPath withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSURL *source in urls) {
        NSString *name = source.lastPathComponent.length ? source.lastPathComponent : NSUUID.UUID.UUIDString;
        NSURL *destination = [NSURL fileURLWithPath:[self.importsPath stringByAppendingPathComponent:name]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:destination.path]) destination = [NSURL fileURLWithPath:[self.importsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]]];
        BOOL scoped = [source startAccessingSecurityScopedResource];
        [[NSFileManager defaultManager] copyItemAtURL:source toURL:destination error:nil];
        if (scoped) [source stopAccessingSecurityScopedResource];
    }
    [self reloadItems];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.items.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"game" forIndexPath:indexPath];
    NSURL *url = self.items[indexPath.row];
    UIListContentConfiguration *content = [UIListContentConfiguration subtitleCellConfiguration];
    content.text = url.lastPathComponent;
    content.secondaryText = @"Imported PS3 boot content";
    content.image = [UIImage systemImageNamed:@"gamecontroller.fill"];
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSURL *url = self.items[indexPath.row];
    int ready = rpcs3_ios_core_boot_elf(url.path.fileSystemRepresentation);
    RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics();
    NSString *message = d.message ? [NSString stringWithUTF8String:d.message] : @"No loader message";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(ready ? @"Ready" : @"Loader result") message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

@interface RPCS3ManageController : UIViewController <UIDocumentPickerDelegate>
@property(nonatomic) NSInteger kind;
@property(nonatomic, strong) UILabel *status;
@end

@implementation RPCS3ManageController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Manage";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UILabel *heading = [[UILabel alloc] init]; heading.text = @"RPCS3 Content Manager"; heading.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    UILabel *detail = [[UILabel alloc] init]; detail.text = @"Install firmware and import user-owned key material into the RPCS3 sandbox."; detail.numberOfLines = 0;
    UIButton *firmware = [UIButton buttonWithType:UIButtonTypeSystem]; [firmware setTitle:@"Install Firmware" forState:UIControlStateNormal]; [firmware addTarget:self action:@selector(importFirmware) forControlEvents:UIControlEventTouchUpInside];
    UIButton *keys = [UIButton buttonWithType:UIButtonTypeSystem]; [keys setTitle:@"Import Keys" forState:UIControlStateNormal]; [keys addTarget:self action:@selector(importKeys) forControlEvents:UIControlEventTouchUpInside];
    self.status = [[UILabel alloc] init]; self.status.numberOfLines = 0;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[heading, detail, firmware, keys, self.status]];
    stack.translatesAutoresizingMaskIntoConstraints = NO; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 16;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20]]];
    [self updateStatus];
}
- (NSString *)pathForKind { return [RPCS3Root() stringByAppendingPathComponent:(self.kind == 1 ? @"keys" : @"firmware")]; }
- (void)pick:(NSInteger)kind { self.kind = kind; UIDocumentPickerViewController *p = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES]; p.delegate = self; p.allowsMultipleSelection = kind == 1; [self presentViewController:p animated:YES completion:nil]; }
- (void)importFirmware { [self pick:0]; }
- (void)importKeys { [self pick:1]; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller; NSString *directory = self.pathForKind; [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSURL *source in urls) { NSURL *destination = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:source.lastPathComponent ?: NSUUID.UUID.UUIDString]]; [[NSFileManager defaultManager] removeItemAtURL:destination error:nil]; BOOL scoped = [source startAccessingSecurityScopedResource]; [[NSFileManager defaultManager] copyItemAtURL:source toURL:destination error:nil]; if (scoped) [source stopAccessingSecurityScopedResource]; }
    [self updateStatus];
}
- (void)updateStatus { NSUInteger f = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[RPCS3Root() stringByAppendingPathComponent:@"firmware"] error:nil].count; NSUInteger k = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[RPCS3Root() stringByAppendingPathComponent:@"keys"] error:nil].count; self.status.text = [NSString stringWithFormat:@"Firmware files: %lu\nKey files: %lu", (unsigned long)f, (unsigned long)k]; }
@end

@interface RPCS3InfoController : UIViewController
@property(nonatomic, strong) UITextView *textView;
@end
@implementation RPCS3InfoController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Status"; self.view.backgroundColor = UIColor.systemBackgroundColor; self.textView = [[UITextView alloc] init]; self.textView.translatesAutoresizingMaskIntoConstraints = NO; self.textView.editable = NO; self.textView.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; [self.view addSubview:self.textView]; [NSLayoutConstraint activateConstraints:@[[self.textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[self.textView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[self.textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics(); NSString *m = d.message ? [NSString stringWithUTF8String:d.message] : @"none"; self.textView.text = [NSString stringWithFormat:@"RPCS3 iOS\n\nCore state: %d\nPlatform: %@\nPPU: %@\nSPU: %@\nJIT: %@\nMetal: %@\nRoot: %@\n\n%@", d.state, d.platform_initialized?@"ready":@"not ready", d.ppu_interpreter_available?@"ready":@"pending", d.spu_interpreter_available?@"ready":@"pending", d.jit_available?@"available":@"unavailable", d.renderer_available?@"available":@"unavailable", RPCS3Root(), m]; }
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application; (void)launchOptions; rpcs3_ios_core_initialize(nullptr);
    RPCS3LibraryController *games = [[RPCS3LibraryController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    RPCS3ManageController *manage = [[RPCS3ManageController alloc] init];
    RPCS3InfoController *status = [[RPCS3InfoController alloc] init];
    UINavigationController *g = [[UINavigationController alloc] initWithRootViewController:games];
    UINavigationController *m = [[UINavigationController alloc] initWithRootViewController:manage];
    UINavigationController *s = [[UINavigationController alloc] initWithRootViewController:status];
    g.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Games" image:[UIImage systemImageNamed:@"square.grid.2x2"] tag:0];
    m.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Manage" image:[UIImage systemImageNamed:@"tray.and.arrow.down"] tag:1];
    s.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Status" image:[UIImage systemImageNamed:@"waveform.path.ecg"] tag:2];
    UITabBarController *tabs = [[UITabBarController alloc] init]; tabs.viewControllers = @[g,m,s];
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController = tabs; [self.window makeKeyAndVisible]; return YES;
}
@end

int main(int argc, char *argv[]) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); } }
