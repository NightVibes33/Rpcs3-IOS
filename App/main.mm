#import <UIKit/UIKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "RPCS3CoreBridge.h"
#import "RPCS3GameLibrary.h"
#import "RPCS3GameDetails.h"
#import "RPCS3LaunchSession.h"
#import "RPCS3Sidebar.h"
#import "RPCS3Settings.h"
#import "RPCS3Utilities.h"
#import "RPCS3UpstreamMenuModel.h"
#import "RPCS3UpstreamUIController.h"

static NSString *RPCS3Root(void) {
    RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics();
    return d.data_path ? ([NSString stringWithUTF8String:d.data_path] ?: @"") : @"";
}

@interface RPCS3GameCell : UICollectionViewCell
@property(nonatomic,strong) UIImageView *art;
@property(nonatomic,strong) UILabel *titleLabel;
@property(nonatomic,strong) UILabel *detailLabel;
@end
@implementation RPCS3GameCell
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self=[super initWithFrame:frame])) {
        self.contentView.backgroundColor = UIColor.secondarySystemBackgroundColor;
        self.contentView.layer.cornerRadius = 14;
        self.contentView.layer.masksToBounds = YES;
        self.art = [[UIImageView alloc] init]; self.art.translatesAutoresizingMaskIntoConstraints = NO; self.art.contentMode = UIViewContentModeScaleAspectFill; self.art.clipsToBounds = YES; self.art.backgroundColor = UIColor.tertiarySystemBackgroundColor;
        self.titleLabel = [[UILabel alloc] init]; self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO; self.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; self.titleLabel.adjustsFontForContentSizeCategory = YES; self.titleLabel.numberOfLines = 2;
        self.detailLabel = [[UILabel alloc] init]; self.detailLabel.translatesAutoresizingMaskIntoConstraints = NO; self.detailLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleCaption1]; self.detailLabel.adjustsFontForContentSizeCategory = YES; self.detailLabel.textColor = UIColor.secondaryLabelColor; self.detailLabel.numberOfLines = 2;
        [self.contentView addSubview:self.art]; [self.contentView addSubview:self.titleLabel]; [self.contentView addSubview:self.detailLabel];
        [NSLayoutConstraint activateConstraints:@[[self.art.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],[self.art.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],[self.art.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],[self.art.heightAnchor constraintEqualToAnchor:self.art.widthAnchor multiplier:0.56],[self.titleLabel.topAnchor constraintEqualToAnchor:self.art.bottomAnchor constant:10],[self.titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:12],[self.titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-12],[self.detailLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],[self.detailLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],[self.detailLabel.trailingAnchor constraintEqualToAnchor:self.titleLabel.trailingAnchor],[self.detailLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.contentView.bottomAnchor constant:-12]]];
    }
    return self;
}
@end

@interface RPCS3LibraryController : UICollectionViewController <UIDocumentPickerDelegate, UISearchResultsUpdating>
@property(nonatomic,strong) NSArray<RPCS3GameEntry *> *allItems;
@property(nonatomic,strong) NSArray<RPCS3GameEntry *> *items;
@end
@implementation RPCS3LibraryController
- (instancetype)init {
    UICollectionViewCompositionalLayout *layout = [[UICollectionViewCompositionalLayout alloc] initWithSectionProvider:^NSCollectionLayoutSection *(NSInteger section,id<NSCollectionLayoutEnvironment> env){
        (void)section; CGFloat width=env.container.effectiveContentSize.width; NSInteger columns=width>=1100?5:width>=800?4:width>=560?3:width>=360?2:1; CGFloat spacing=width>=700?18:12;
        NSCollectionLayoutSize *itemSize=[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1] heightDimension:[NSCollectionLayoutDimension estimatedDimension:205]];
        NSCollectionLayoutItem *item=[NSCollectionLayoutItem itemWithLayoutSize:itemSize];
        NSCollectionLayoutSize *groupSize=[NSCollectionLayoutSize sizeWithWidthDimension:[NSCollectionLayoutDimension fractionalWidthDimension:1] heightDimension:[NSCollectionLayoutDimension estimatedDimension:205]];
        NSCollectionLayoutGroup *group=[NSCollectionLayoutGroup horizontalGroupWithLayoutSize:groupSize subitem:item count:columns]; group.interItemSpacing=[NSCollectionLayoutSpacing fixedSpacing:spacing];
        NSCollectionLayoutSection *result=[NSCollectionLayoutSection sectionWithGroup:group]; result.interGroupSpacing=spacing; result.contentInsets=NSDirectionalEdgeInsetsMake(spacing,spacing,spacing,spacing); return result;
    }];
    return [super initWithCollectionViewLayout:layout];
}
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"RPCS3"; self.collectionView.backgroundColor=UIColor.systemBackgroundColor; [self.collectionView registerClass:RPCS3GameCell.class forCellWithReuseIdentifier:@"game"];
    self.navigationItem.rightBarButtonItems=@[[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(importGame)],[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(reloadItems)]];
    __weak RPCS3LibraryController *weakSelf=self;
    UIMenu *upstreamMenu=RPCS3CreateUpstreamMainMenu(^(NSString *identifier){ [weakSelf runUpstreamAction:identifier]; });
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"line.3.horizontal"] menu:upstreamMenu];
    UISearchController *search=[[UISearchController alloc] initWithSearchResultsController:nil]; search.searchResultsUpdater=self; search.obscuresBackgroundDuringPresentation=NO; search.searchBar.placeholder=@"Search games or title IDs"; self.navigationItem.searchController=search; self.navigationItem.hidesSearchBarWhenScrolling=NO; [self reloadItems];
}
- (void)runUpstreamAction:(NSString *)identifier {
    NSDictionary<NSString *,NSArray<NSString *> *> *routes=@{
        @"confCPUAct":@[@"settings_dialog.ui",@"coreTab"], @"confGPUAct":@[@"settings_dialog.ui",@"gpuTab"],
        @"confAudioAct":@[@"settings_dialog.ui",@"audioTab"], @"confIOAct":@[@"settings_dialog.ui",@"ioTab"],
        @"confSystemAct":@[@"settings_dialog.ui",@"systemTab"], @"confNetwrkAct":@[@"settings_dialog.ui",@"networkTab"],
        @"confAdvAct":@[@"settings_dialog.ui",@"advancedTab"], @"confEmuAct":@[@"settings_dialog.ui",@"emulatorTab"],
        @"confGuiAct":@[@"settings_dialog.ui",@"guiTab"], @"confPadsAct":@[@"pad_settings_dialog.ui",@""],
        @"confCamerasAct":@[@"camera_settings_dialog.ui",@""], @"actionPS_Move_Tracker":@[@"ps_move_tracker_dialog.ui",@""],
        @"confShortcutsAct":@[@"shortcut_dialog.ui",@""], @"actionMusic_Player":@[@"music_player_dialog.ui",@""],
        @"patchCreatorAct":@[@"patch_creator_dialog.ui",@""], @"actionManage_Game_Patches":@[@"patch_manager_dialog.ui",@""],
        @"toolsVfsDialogAct":@[@"vfs_tool_dialog.ui",@""], @"aboutAct":@[@"about_dialog.ui",@""]
    };
    NSArray<NSString *> *route=routes[identifier];
    if(route){[self.navigationController pushViewController:[[RPCS3UpstreamUIDocumentController alloc] initWithDocumentFile:route[0] preferredPageName:route[1]] animated:YES];return;}
    if([identifier isEqualToString:@"bootGameAct"]||[identifier isEqualToString:@"addGamesAct"]||[identifier isEqualToString:@"addIsoGamesAct"]){[self importGame];return;}
    if([identifier isEqualToString:@"refreshGameListAct"]){[self reloadItems];return;}
    if([identifier isEqualToString:@"sysStopAct"]){rpcs3_ios_core_stop();return;}
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:identifier message:@"This original RPCS3 QAction is preserved in the converted menu. Its emulator-core command is not connected yet." preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]]; [self presentViewController:alert animated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self reloadItems]; }
- (void)reloadItems { self.allItems=[RPCS3GameLibrary scanRoot:RPCS3Root()]; [self updateSearchResultsForSearchController:self.navigationItem.searchController]; }
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { NSString *q=searchController.searchBar.text.lowercaseString; self.items=q.length?[self.allItems filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(RPCS3GameEntry *e,NSDictionary *b){(void)b;return [e.title.lowercaseString containsString:q]||[e.titleID.lowercaseString containsString:q];}]]:self.allItems; [self.collectionView reloadData]; }
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section { (void)collectionView;(void)section;return self.items.count; }
- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    RPCS3GameCell *cell=[collectionView dequeueReusableCellWithReuseIdentifier:@"game" forIndexPath:indexPath]; RPCS3GameEntry *entry=self.items[indexPath.item]; UIImage *art=entry.iconURL?[UIImage imageWithContentsOfFile:entry.iconURL.path]:nil; cell.art.image=art?:[UIImage systemImageNamed:@"gamecontroller.fill"]; cell.art.contentMode=art?UIViewContentModeScaleAspectFill:UIViewContentModeScaleAspectFit; cell.art.tintColor=UIColor.systemBlueColor; cell.titleLabel.text=entry.title;
    NSMutableArray *details=[NSMutableArray array]; if(entry.titleID.length)[details addObject:entry.titleID]; if(entry.category.length)[details addObject:entry.category]; if(entry.version.length)[details addObject:[@"v" stringByAppendingString:entry.version]]; cell.detailLabel.text=details.count?[details componentsJoinedByString:@" • "]:@"PS3 content"; return cell;
}
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath { [collectionView deselectItemAtIndexPath:indexPath animated:YES]; [self.navigationController pushViewController:[[RPCS3GameDetailsController alloc] initWithEntry:self.items[indexPath.item]] animated:YES]; }
- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    (void)collectionView;(void)point; RPCS3GameEntry *entry=self.items[indexPath.item]; __weak RPCS3LibraryController *weakSelf=self;
    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:^UIViewController *{ return [[RPCS3GameDetailsController alloc] initWithEntry:entry]; } actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){ (void)suggested;
        UIAction *details=[UIAction actionWithTitle:@"Game Details" image:[UIImage systemImageNamed:@"info.circle"] identifier:nil handler:^(__kindof UIAction *a){(void)a;[weakSelf.navigationController pushViewController:[[RPCS3GameDetailsController alloc] initWithEntry:entry] animated:YES];}];
        UIAction *boot=[UIAction actionWithTitle:@"Launch Session" image:[UIImage systemImageNamed:@"play.fill"] identifier:nil handler:^(__kindof UIAction *a){(void)a;[weakSelf.navigationController pushViewController:[[RPCS3LaunchSessionController alloc] initWithEntry:entry] animated:YES];}]; boot.attributes=entry.bootURL?0:UIMenuElementAttributesDisabled;
        return [UIMenu menuWithTitle:entry.title children:@[boot,details]];
    }];
}
- (void)importGame { UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData,UTTypeFolder] asCopy:YES]; picker.delegate=self; picker.allowsMultipleSelection=YES; [self presentViewController:picker animated:YES completion:nil]; }
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { (void)controller; NSString *imports=[RPCS3Root() stringByAppendingPathComponent:@"imports"]; [NSFileManager.defaultManager createDirectoryAtPath:imports withIntermediateDirectories:YES attributes:nil error:nil]; for(NSURL *source in urls){ NSString *name=source.lastPathComponent.length?source.lastPathComponent:NSUUID.UUID.UUIDString; NSURL *destination=[NSURL fileURLWithPath:[imports stringByAppendingPathComponent:name]]; if([NSFileManager.defaultManager fileExistsAtPath:destination.path])destination=[NSURL fileURLWithPath:[imports stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@",NSUUID.UUID.UUIDString,name]]]; BOOL scoped=[source startAccessingSecurityScopedResource]; [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:nil]; if(scoped)[source stopAccessingSecurityScopedResource]; } [self reloadItems]; }
@end

@interface RPCS3ManageController : UITableViewController <UIDocumentPickerDelegate>
@property(nonatomic) NSInteger kind;
@end
@implementation RPCS3ManageController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Manage"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView;return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView;return section==0?3:2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView;return section==0?@"Install":@"Configuration"; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"row"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"row"]; NSArray *titles=indexPath.section==0?@[@"Install Firmware",@"Install Packages",@"Import Keys / Licenses"]:@[@"Settings",@"Pads"]; NSArray *icons=indexPath.section==0?@[@"shippingbox",@"archivebox",@"key"]:@[@"gearshape",@"gamecontroller"]; cell.textLabel.text=titles[indexPath.row]; cell.imageView.image=[UIImage systemImageNamed:icons[indexPath.row]]; cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if(indexPath.section==1){NSString *file=indexPath.row==0?@"settings_dialog.ui":@"pad_settings_dialog.ui";[self.navigationController pushViewController:[[RPCS3UpstreamUIDocumentController alloc] initWithDocumentFile:file] animated:YES];return;}
    self.kind=indexPath.row; UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeData] asCopy:YES]; picker.delegate=self; picker.allowsMultipleSelection=indexPath.row==2; [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls { (void)controller; NSString *folder=self.kind==0?@"firmware":self.kind==1?@"packages":@"keys"; NSString *path=[RPCS3Root() stringByAppendingPathComponent:folder]; [NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]; for(NSURL *source in urls){ BOOL scoped=[source startAccessingSecurityScopedResource]; NSURL *destination=[NSURL fileURLWithPath:[path stringByAppendingPathComponent:source.lastPathComponent?:NSUUID.UUID.UUIDString]]; [NSFileManager.defaultManager removeItemAtURL:destination error:nil]; [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:nil]; if(scoped)[source stopAccessingSecurityScopedResource]; } }
@end

static UINavigationController *RPCS3GamesNavigation(void) { return [[UINavigationController alloc] initWithRootViewController:[[RPCS3LibraryController alloc] init]]; }
static UINavigationController *RPCS3ManageNavigation(void) { return [[UINavigationController alloc] initWithRootViewController:[[RPCS3ManageController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; }
static UINavigationController *RPCS3UtilitiesNavigation(void) { return [[UINavigationController alloc] initWithRootViewController:[[RPCS3UtilitiesController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; }
static UINavigationController *RPCS3UpstreamNavigation(void) { return [[UINavigationController alloc] initWithRootViewController:[[RPCS3UpstreamUIBrowserController alloc] initWithStyle:UITableViewStyleInsetGrouped]]; }

static UITabBarController *RPCS3Tabs(void) {
    UINavigationController *games=RPCS3GamesNavigation(),*manage=RPCS3ManageNavigation(),*utilities=RPCS3UtilitiesNavigation(),*upstream=RPCS3UpstreamNavigation();
    games.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Games" image:[UIImage systemImageNamed:@"square.grid.2x2"] tag:0]; manage.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Manage" image:[UIImage systemImageNamed:@"tray.full"] tag:1]; utilities.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"Utilities" image:[UIImage systemImageNamed:@"wrench.and.screwdriver"] tag:2]; upstream.tabBarItem=[[UITabBarItem alloc] initWithTitle:@"RPCS3 UI" image:[UIImage systemImageNamed:@"rectangle.3.group"] tag:3]; UITabBarController *tabs=[[UITabBarController alloc] init]; tabs.viewControllers=@[games,manage,utilities,upstream]; return tabs;
}
static UIViewController *RPCS3RootController(void) {
    if(UIDevice.currentDevice.userInterfaceIdiom!=UIUserInterfaceIdiomPad)return RPCS3Tabs();
    UISplitViewController *split=[[UISplitViewController alloc] initWithStyle:UISplitViewControllerStyleDoubleColumn];
    NSArray<UIViewController *> *destinations=@[RPCS3GamesNavigation(),RPCS3ManageNavigation(),RPCS3UtilitiesNavigation(),RPCS3UpstreamNavigation()];
    RPCS3SidebarController *sidebar=[[RPCS3SidebarController alloc] initWithSplitViewController:split titles:@[@"Games",@"Manage",@"Utilities",@"RPCS3 UI"] icons:@[@"square.grid.2x2",@"tray.full",@"wrench.and.screwdriver",@"rectangle.3.group"] destinations:destinations];
    [split setViewController:[[UINavigationController alloc] initWithRootViewController:sidebar] forColumn:UISplitViewControllerColumnPrimary]; [split setViewController:destinations.firstObject forColumn:UISplitViewControllerColumnSecondary]; split.preferredDisplayMode=UISplitViewControllerDisplayModeOneBesideSecondary; split.preferredPrimaryColumnWidthFraction=0.24; split.minimumPrimaryColumnWidth=240; split.maximumPrimaryColumnWidth=320; return split;
}

@interface AppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions { (void)application;(void)launchOptions;rpcs3_ios_core_initialize(nullptr);self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];self.window.rootViewController=RPCS3RootController();[self.window makeKeyAndVisible];return YES; }
@end
int main(int argc,char *argv[]){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(AppDelegate.class));}}
