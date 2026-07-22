#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "RPCS3CoreBridge.h"

static NSString *RPCS3Root(void) {
    RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics();
    return d.data_path ? ([NSString stringWithUTF8String:d.data_path] ?: @"") : @"";
}

static UIImage *RPCS3Placeholder(void) {
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:44 weight:UIImageSymbolWeightMedium];
    return [UIImage systemImageNamed:@"gamecontroller.fill" withConfiguration:config];
}

@interface RPCS3GameCell : UICollectionViewCell
@property(nonatomic,strong) UIImageView *art;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *detailLabel;
@end
@implementation RPCS3GameCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.contentView.layer.cornerRadius = 14;
        self.contentView.layer.masksToBounds = YES;
        self.art = [[UIImageView alloc] initWithImage:RPCS3Placeholder()];
        self.art.translatesAutoresizingMaskIntoConstraints = NO;
        self.art.contentMode = UIViewContentModeScaleAspectFit;
        self.art.tintColor = UIColor.systemBlueColor;
        self.art.backgroundColor = UIColor.tertiarySystemBackgroundColor;
        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        self.titleLabel.numberOfLines = 2;
        self.detailLabel = [[UILabel alloc] init];
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        self.detailLabel.textColor = UIColor.secondaryLabelColor;
        [self.contentView addSubview:self.art]; [self.contentView addSubview:self.titleLabel]; [self.contentView addSubview:self.detailLabel];
        [NSLayoutConstraint activateConstraints:@[
            [self.art.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
            [self.art.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
            [self.art.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
            [self.art.heightAnchor constraintEqualToAnchor:self.art.widthAnchor multiplier:0.56],
            [self.titleLabel.topAnchor constraintEqualToAnchor:self.art.bottomAnchor constant:10],
            [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],
            [self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],
            [self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
            [self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
            [self.detailLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],
            [self.detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12]
        ]];
    }
    return self;
}
@end

@interface RPCS3LibraryController : UICollectionViewController <UIDocumentPickerDelegate, UISearchResultsUpdating>
@property(nonatomic,strong) NSArray<NSURL *> *allItems;
@property(nonatomic,strong) NSArray<NSURL *> *items;
@end

@implementation RPCS3LibraryController
- (instancetype)init {
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> env) {
        (void)section;
        CGFloat width = env.container.effectiveContentSize.width;
        NSInteger columns = width >= 1100 ? 5 : width >= 800 ? 4 : width >= 560 ? 3 : width >= 360 ? 2 : 1;
        CGFloat spacing = width >= 700 ? 18 : 12;
        NSCollectionLayoutSize *itemSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0] heightDimension:[NSCollectionLayoutDimension estimatedDimension:190]];
        NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
        NSCollectionLayoutSize *groupSize = [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1.0] heightDimension:[NSCollectionLayoutDimension estimatedDimension:190]];
        NSCollectionLayoutGroup *group = [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
        group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:spacing];
        NSCollectionLayoutSection *result = [NSCollectionLayoutSection sectionWithGroup:group];
        result.interGroupSpacing = spacing;
        result.contentInsets = NSDirectionalEdgeInsetsMake(spacing, spacing, spacing, spacing);
        return result;
    }];
    return [super initWithCollectionViewLayout:layout];
}
- (NSString *)importsPath { return [RPCS3Root() stringByAppendingPathComponent:@"imports"]; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"RPCS3";
    self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
    [self.collectionView registerClass:RPCS3GameCell.class forCellWithReuseIdentifier:@"game"];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importGame)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal.decrease.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showMenu)]
    ];
    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self; search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Search games";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    [self reloadItems];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadItems]; }
- (void)reloadItems {
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[NSURL fileURLWithPath:self.importsPath] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil] ?: @[];
    self.allItems = [files sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b){ return [a.lastPathComponent localizedCaseInsensitiveCompare:b.lastPathComponent]; }];
    [self updateSearchResultsForSearchController:self.navigationItem.searchController];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *q = searchController.searchBar.text.lowercaseString;
    self.items = q.length ? [self.allItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSURL *url, NSDictionary *bindings){ (void)bindings; return [url.lastPathComponent.lowercaseString containsString:q]; }]] : self.allItems;
    [self.collectionView reloadData];
}
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { (void)collectionView; (void)section; return self.items.count; }
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RPCS3GameCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"game" forIndexPath:indexPath];
    NSURL *url = self.items[indexPath.item];
    cell.titleLabel.text = url.lastPathComponent.stringByDeletingPathExtension;
    cell.detailLabel.text = url.pathExtension.length ? url.pathExtension.uppercaseString : @"PS3 CONTENT";
    return cell;
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    NSURL *url = self.items[indexPath.item];
    int ready = rpcs3_ios_core_boot_elf(url.path.fileSystemRepresentation);
    RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics();
    NSString *message = d.message ? [NSString stringWithUTF8String:d.message] : @"No loader message";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:(ready ? @"Ready to boot" : @"Loader result") message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)importGame {
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES];
    picker.delegate = self; picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    [[NSFileManager defaultManager] createDirectoryAtPath:self.importsPath withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSURL *source in urls) {
        NSString *name = source.lastPathComponent.length ? source.lastPathComponent : NSUUID.UUID.UUIDString;
        NSURL *dest = [NSURL fileURLWithPath:[self.importsPath stringByAppendingPathComponent:name]];
        if ([[NSFileManager defaultManager] fileExistsAtPath:dest.path]) dest = [NSURL fileURLWithPath:[self.importsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]]];
        BOOL scoped = [source startAccessingSecurityScopedResource];
        [[NSFileManager defaultManager] copyItemAtURL:source toURL:dest error:nil];
        if (scoped) [source stopAccessingSecurityScopedResource];
    }
    [self reloadItems];
}
- (void)showMenu {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"RPCS3" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Refresh Game List" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){ [self reloadItems]; }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItems.lastObject;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

@interface RPCS3ManageController : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic) NSInteger kind;
@end
@implementation RPCS3ManageController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Manage"; self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return section == 0 ? 3 : 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; return section == 0 ? @"Install" : @"Configuration"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"row"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"];
    NSArray *titles = indexPath.section == 0 ? @[@"Install Firmware", @"Install Packages", @"Import Keys / Licenses"] : @[@"Settings", @"Pads"];
    NSArray *icons = indexPath.section == 0 ? @[@"shippingbox", @"archivebox", @"key"] : @[@"gearshape", @"gamecontroller"];
    cell.textLabel.text = titles[indexPath.row]; cell.imageView.image = [UIImage systemImageNamed:icons[indexPath.row]]; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        self.kind = indexPath.row;
        UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES]; picker.delegate = self; picker.allowsMultipleSelection = indexPath.row == 2; [self presentViewController:picker animated:YES completion:nil];
    }
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSString *folder = self.kind == 0 ? @"firmware" : self.kind == 1 ? @"packages" : @"keys";
    NSString *path = [RPCS3Root() stringByAppendingPathComponent:folder];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    for (NSURL *source in urls) { BOOL scoped = [source startAccessingSecurityScopedResource]; NSURL *dest = [NSURL fileURLWithPath:[path stringByAppendingPathComponent:source.lastPathComponent ?: NSUUID.UUID.UUIDString]]; [[NSFileManager defaultManager] removeItemAtURL:dest error:nil]; [[NSFileManager defaultManager] copyItemAtURL:source toURL:dest error:nil]; if (scoped) [source stopAccessingSecurityScopedResource]; }
}
@end

@interface RPCS3StatusController : UIViewController
@end
@implementation RPCS3StatusController
- (void)viewDidLoad { [super viewDidLoad]; self.title = @"Utilities"; self.view.backgroundColor = UIColor.systemBackgroundColor; UILabel *label = [[UILabel alloc] init]; label.translatesAutoresizingMaskIntoConstraints = NO; label.numberOfLines = 0; label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics(); label.text = [NSString stringWithFormat:@"Core state: %d\nMetal: %@\nJIT: %@\nData: %@", d.state, d.renderer_available?@"Available":@"Unavailable", d.jit_available?@"Available":@"Unavailable", RPCS3Root()]; [self.view addSubview:label]; [NSLayoutConstraint activateConstraints:@[[label.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:24],[label.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],[label.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20]]]; }
@end

static UIViewController *RPCS3RootController(void) {
    RPCS3LibraryController *games = [[RPCS3LibraryController alloc] init];
    RPCS3ManageController *manage = [[RPCS3ManageController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    RPCS3StatusController *utilities = [[RPCS3StatusController alloc] init];
    UINavigationController *g = [[UINavigationController alloc] initWithRootViewController:games];
    UINavigationController *m = [[UINavigationController alloc] initWithRootViewController:manage];
    UINavigationController *u = [[UINavigationController alloc] initWithRootViewController:utilities];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UISplitViewController *split = [[UISplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
        UITableViewController *sidebar = [[UITableViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        sidebar.title = @"RPCS3";
        [split setViewController:[[UINavigationController alloc] initWithRootViewController:sidebar] forColumn:UISplitViewControllerColumnPrimary];
        [split setViewController:g forColumn:UISplitViewControllerColumnSecondary];
        split.preferredDisplayMode = UISplitViewControllerDisplayModeOneBesideSecondary;
        split.preferredPrimaryColumnWidthFraction = 0.25;
        return split;
    }
    g.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Games" image:[UIImage systemImageNamed:@"square.grid.2x2"] tag:0];
    m.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Manage" image:[UIImage systemImageNamed:@"tray.full"] tag:1];
    u.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Utilities" image:[UIImage systemImageNamed:@"wrench.and.screwdriver"] tag:2];
    UITabBarController *tabs = [[UITabBarController alloc] init]; tabs.viewControllers = @[g,m,u]; return tabs;
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions { (void)application; (void)launchOptions; rpcs3_ios_core_initialize(nullptr); self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds]; self.window.rootViewController = RPCS3RootController(); [self.window makeKeyAndVisible]; return YES; }
@end

int main(int argc, char *argv[]) { @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class)); } }
