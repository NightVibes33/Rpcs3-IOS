#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "RPCS3CoreBridge.h"
#import "RPCS3GameLibrary.h"
#import "RPCS3GameDetails.h"
#import "RPCS3LaunchSession.h"
#import "RPCS3UpstreamMenuModel.h"
#import "RPCS3UpstreamUIController.h"

static NSString *RPCS3Root(void) {
    RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    return diagnostics.data_path ? ([NSString stringWithUTF8String:diagnostics.data_path] ?: @"") : @"";
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

        self.art = [[UIImageView alloc] init];
        self.art.translatesAutoresizingMaskIntoConstraints = NO;
        self.art.contentMode = UIViewContentModeScaleAspectFill;
        self.art.clipsToBounds = YES;
        self.art.backgroundColor = UIColor.tertiarySystemBackgroundColor;

        self.titleLabel = [[UILabel alloc] init];
        self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        self.titleLabel.adjustsFontForContentSizeCategory = YES;
        self.titleLabel.numberOfLines = 2;

        self.detailLabel = [[UILabel alloc] init];
        self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO;
        self.detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1];
        self.detailLabel.adjustsFontForContentSizeCategory = YES;
        self.detailLabel.textColor = UIColor.secondaryLabelColor;
        self.detailLabel.numberOfLines = 2;

        [self.contentView addSubview:self.art];
        [self.contentView addSubview:self.titleLabel];
        [self.contentView addSubview:self.detailLabel];
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
@property(nonatomic,strong) NSArray<RPCS3GameEntry *> *allItems;
@property(nonatomic,strong) NSArray<RPCS3GameEntry *> *items;
@property(nonatomic,copy) NSString *pickerFolder;
@end

@implementation RPCS3LibraryController
- (instancetype)init {
    UICollectionViewCompositionalLayout *layout =
        [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section, id<NSCollectionLayoutEnvironment> environment) {
            (void)section;
            CGFloat width = environment.container.effectiveContentSize.width;
            NSInteger columns = width >= 1100 ? 5 : width >= 800 ? 4 : width >= 560 ? 3 : width >= 360 ? 2 : 1;
            CGFloat spacing = width >= 700 ? 18 : 12;
            NSCollectionLayoutSize *itemSize =
                [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                                               heightDimension:[NSCollectionLayoutDimension estimatedDimension:205]];
            NSCollectionLayoutItem *item = [NSCollectionLayoutItem itemWithLayoutSize:itemSize];
            NSCollectionLayoutSize *groupSize =
                [NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1]
                                               heightDimension:[NSCollectionLayoutDimension estimatedDimension:205]];
            NSCollectionLayoutGroup *group =
                [NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns];
            group.interItemSpacing = [NSCollectionLayoutSpacing fixedSpacing:spacing];
            NSCollectionLayoutSection *result = [NSCollectionLayoutSection sectionWithGroup:group];
            result.interGroupSpacing = spacing;
            result.contentInsets = NSDirectionalEdgeInsetsMake(spacing, spacing, spacing, spacing);
            return result;
        }];
    return [super initWithCollectionViewLayout:layout];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"RPCS3";
    self.collectionView.backgroundColor = UIColor.systemBackgroundColor;
    [self.collectionView registerClass:RPCS3GameCell.class forCellWithReuseIdentifier:@"game"];

    __weak RPCS3LibraryController *weakSelf = self;
    UIMenu *mainMenu = RPCS3CreateUpstreamMainMenu(^(NSString *identifier) {
        [weakSelf runUpstreamAction:identifier];
    });
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"] menu:mainMenu];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importGames)],
        [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"]
                                         style:UIBarButtonItemStylePlain
                                        target:self
                                        action:@selector(reloadItems)]
    ];

    UISearchController *search = [[UISearchController alloc] initWithSearchResultsController:nil];
    search.searchResultsUpdater = self;
    search.obscuresBackgroundDuringPresentation = NO;
    search.searchBar.placeholder = @"Search games or title IDs";
    self.navigationItem.searchController = search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    [self reloadItems];
}

- (void)runUpstreamAction:(NSString *)identifier {
    NSDictionary<NSString *,NSArray<NSString *> *> *routes = @{
        @"confCPUAct": @[@"settings_dialog.ui", @"coreTab"],
        @"confGPUAct": @[@"settings_dialog.ui", @"gpuTab"],
        @"confAudioAct": @[@"settings_dialog.ui", @"audioTab"],
        @"confIOAct": @[@"settings_dialog.ui", @"ioTab"],
        @"confSystemAct": @[@"settings_dialog.ui", @"systemTab"],
        @"confNetwrkAct": @[@"settings_dialog.ui", @"networkTab"],
        @"confAdvAct": @[@"settings_dialog.ui", @"advancedTab"],
        @"confEmuAct": @[@"settings_dialog.ui", @"emulatorTab"],
        @"confGuiAct": @[@"settings_dialog.ui", @"guiTab"],
        @"confPadsAct": @[@"pad_settings_dialog.ui", @""],
        @"confCamerasAct": @[@"camera_settings_dialog.ui", @""],
        @"actionPS_Move_Tracker": @[@"ps_move_tracker_dialog.ui", @""],
        @"confShortcutsAct": @[@"shortcut_dialog.ui", @""],
        @"actionMusic_Player": @[@"music_player_dialog.ui", @""],
        @"patchCreatorAct": @[@"patch_creator_dialog.ui", @""],
        @"actionManage_Game_Patches": @[@"patch_manager_dialog.ui", @""],
        @"toolsVfsDialogAct": @[@"vfs_tool_dialog.ui", @""],
        @"aboutAct": @[@"about_dialog.ui", @""]
    };

    NSArray<NSString *> *route = routes[identifier];
    if (route) {
        [self.navigationController pushViewController:
            [[RPCS3UpstreamUIDocumentController alloc] initWithDocumentFile:route[0] preferredPageName:route[1]]
                                                  animated:YES];
        return;
    }

    if ([identifier isEqualToString:@"bootGameAct"] ||
        [identifier isEqualToString:@"bootIsoAct"] ||
        [identifier isEqualToString:@"bootElfAct"] ||
        [identifier isEqualToString:@"addGamesAct"] ||
        [identifier isEqualToString:@"addIsoGamesAct"]) {
        [self importGames];
        return;
    }
    if ([identifier isEqualToString:@"bootInstallPkgAct"]) {
        [self presentImporterForFolder:@"packages" allowsFolders:NO];
        return;
    }
    if ([identifier isEqualToString:@"bootInstallPupAct"]) {
        [self presentImporterForFolder:@"firmware" allowsFolders:NO];
        return;
    }
    if ([identifier isEqualToString:@"actionManage_RAP_Licenses"]) {
        [self presentImporterForFolder:@"keys" allowsFolders:NO];
        return;
    }
    if ([identifier isEqualToString:@"refreshGameListAct"]) {
        [self reloadItems];
        return;
    }
    if ([identifier isEqualToString:@"sysStopAct"]) {
        rpcs3_ios_core_stop();
        return;
    }

    NSString *message = [identifier isEqualToString:@"bootVSHAct"]
        ? @"Boot VSH/XMB is now in the real RPCS3 main menu, but the core bridge still needs a boot_vsh implementation before it can launch the PS3 dashboard."
        : @"This original RPCS3 action is preserved in the main menu, but its emulator-core command is not connected yet.";
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:identifier message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadItems];
}

- (void)reloadItems {
    self.allItems = [RPCS3GameLibrary scanRoot:RPCS3Root()];
    [self updateSearchResultsForSearchController:self.navigationItem.searchController];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text.lowercaseString;
    self.items = query.length
        ? [self.allItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RPCS3GameEntry *entry, NSDictionary *bindings) {
            (void)bindings;
            return [entry.title.lowercaseString containsString:query] ||
                   [entry.titleID.lowercaseString containsString:query];
        }]]
        : self.allItems;
    [self.collectionView reloadData];
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    (void)collectionView;
    (void)section;
    return self.items.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RPCS3GameCell *cell =
        [collectionView dequeueReusableCellWithReuseIdentifier:@"game" forIndexPath:indexPath];
    RPCS3GameEntry *entry = self.items[indexPath.item];
    UIImage *art = entry.iconURL ? [UIImage imageWithContentsOfFile:entry.iconURL.path] : nil;
    cell.art.image = art ?: [UIImage systemImageNamed:@"gamecontroller.fill"];
    cell.art.contentMode = art ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    cell.art.tintColor = UIColor.systemBlueColor;
    cell.titleLabel.text = entry.title;

    NSMutableArray<NSString *> *details = [NSMutableArray array];
    if (entry.titleID.length) [details addObject:entry.titleID];
    if (entry.category.length) [details addObject:entry.category];
    if (entry.version.length) [details addObject:[@"v" stringByAppendingString:entry.version]];
    cell.detailLabel.text = details.count ? [details componentsJoinedByString:@" • "] : @"PS3 content";
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    [self.navigationController pushViewController:
        [[RPCS3GameDetailsController alloc] initWithEntry:self.items[indexPath.item]]
                                              animated:YES];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView
     contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath
                                          point:(CGPoint)point {
    (void)collectionView;
    (void)point;
    RPCS3GameEntry *entry = self.items[indexPath.item];
    __weak RPCS3LibraryController *weakSelf = self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil
                                                   previewProvider:^UIViewController *{
        return [[RPCS3GameDetailsController alloc] initWithEntry:entry];
    } actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested) {
        (void)suggested;
        UIAction *details =
            [UIAction actionWithTitle:@"Game Details"
                                image:[UIImage systemImageNamed:@"info.circle"]
                           identifier:nil
                              handler:^(__kindof UIAction *action) {
                (void)action;
                [weakSelf.navigationController pushViewController:
                    [[RPCS3GameDetailsController alloc] initWithEntry:entry]
                                                          animated:YES];
            }];
        UIAction *boot =
            [UIAction actionWithTitle:@"Launch Session"
                                image:[UIImage systemImageNamed:@"play.fill"]
                           identifier:nil
                              handler:^(__kindof UIAction *action) {
                (void)action;
                [weakSelf.navigationController pushViewController:
                    [[RPCS3LaunchSessionController alloc] initWithEntry:entry]
                                                          animated:YES];
            }];
        boot.attributes = entry.bootURL ? 0 : UIMenuElementAttributesDisabled;
        return [UIMenu menuWithTitle:entry.title children:@[boot, details]];
    }];
}

- (void)importGames {
    [self presentImporterForFolder:@"imports" allowsFolders:YES];
}

- (void)presentImporterForFolder:(NSString *)folder allowsFolders:(BOOL)allowsFolders {
    self.pickerFolder = folder;
    NSArray<UTType *> *types = allowsFolders ? @[UTTypeData, UTTypeFolder] : @[UTTypeData];
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = YES;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
 didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    NSString *folder = self.pickerFolder.length ? self.pickerFolder : @"imports";
    NSString *destinationDirectory = [RPCS3Root() stringByAppendingPathComponent:folder];
    [NSFileManager.defaultManager createDirectoryAtPath:destinationDirectory
                            withIntermediateDirectories:YES
                                             attributes:nil
                                                  error:nil];

    for (NSURL *source in urls) {
        NSString *name = source.lastPathComponent.length ? source.lastPathComponent : NSUUID.UUID.UUIDString;
        NSURL *destination =
            [NSURL fileURLWithPath:[destinationDirectory stringByAppendingPathComponent:name]];
        if ([NSFileManager.defaultManager fileExistsAtPath:destination.path]) {
            destination = [NSURL fileURLWithPath:
                [destinationDirectory stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]]];
        }
        BOOL scoped = [source startAccessingSecurityScopedResource];
        [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:nil];
        if (scoped) [source stopAccessingSecurityScopedResource];
    }
    self.pickerFolder = nil;
    [self reloadItems];
}
@end

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end

@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application;
    (void)launchOptions;
    rpcs3_ios_core_initialize(nullptr);

    RPCS3LibraryController *mainWindow = [[RPCS3LibraryController alloc] init];
    UINavigationController *navigation =
        [[UINavigationController alloc] initWithRootViewController:mainWindow];
    navigation.navigationBar.prefersLargeTitles = YES;

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = navigation;
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, argv, nil, NSStringFromClass(AppDelegate.class));
    }
}
