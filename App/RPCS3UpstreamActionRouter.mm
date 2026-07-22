#import "RPCS3UpstreamActionRouter.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "RPCS3CoreBridge.h"
#import "RPCS3UpstreamUIController.h"
#import "RPCS3Utilities.h"

typedef NS_ENUM(NSInteger, RPCS3PickerMode) {
    RPCS3PickerModeNone = 0,
    RPCS3PickerModeImportGame,
    RPCS3PickerModeBootExecutable,
    RPCS3PickerModeImportISO,
    RPCS3PickerModeInstallPackage,
    RPCS3PickerModeInstallFirmware,
    RPCS3PickerModeImportLicense,
    RPCS3PickerModeBootSavestate,
    RPCS3PickerModeInsertDisc,
};

@interface RPCS3UpstreamActionRouter ()
@property(nonatomic,weak) UIViewController *owner;
@property(nonatomic,copy) RPCS3UpstreamReloadHandler reloadHandler;
@property(nonatomic) RPCS3PickerMode pickerMode;
@property(nonatomic,copy) NSString *pendingIdentifier;
@end

@implementation RPCS3UpstreamActionRouter

- (instancetype)initWithOwner:(UIViewController *)owner reloadHandler:(RPCS3UpstreamReloadHandler)reloadHandler {
    if ((self = [super init])) {
        _owner = owner;
        _reloadHandler = [reloadHandler copy];
    }
    return self;
}

- (NSString *)dataRoot {
    RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    return diagnostics.data_path ? ([NSString stringWithUTF8String:diagnostics.data_path] ?: @"") : @"";
}

- (void)showTitle:(NSString *)title message:(NSString *)message {
    UIViewController *owner = self.owner;
    if (!owner) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [owner presentViewController:alert animated:YES completion:nil];
}

- (void)pushDocument:(NSString *)file preferredPage:(NSString *)page {
    RPCS3UpstreamUIDocumentController *controller = [[RPCS3UpstreamUIDocumentController alloc] initWithDocumentFile:file preferredPageName:page.length ? page : nil];
    [self.owner.navigationController pushViewController:controller animated:YES];
}

- (void)presentPickerMode:(RPCS3PickerMode)mode identifier:(NSString *)identifier multiple:(BOOL)multiple folders:(BOOL)folders {
    self.pickerMode = mode;
    self.pendingIdentifier = identifier;
    NSMutableArray<UTType *> *types = [NSMutableArray arrayWithObject:UTTypeData];
    if (folders) [types addObject:UTTypeFolder];
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = multiple;
    [self.owner presentViewController:picker animated:YES completion:nil];
}

- (NSString *)folderForMode:(RPCS3PickerMode)mode {
    switch (mode) {
        case RPCS3PickerModeImportGame: return @"imports";
        case RPCS3PickerModeBootExecutable: return @"imports/boot";
        case RPCS3PickerModeImportISO: return @"disc";
        case RPCS3PickerModeInstallPackage: return @"packages";
        case RPCS3PickerModeInstallFirmware: return @"firmware";
        case RPCS3PickerModeImportLicense: return @"keys";
        case RPCS3PickerModeBootSavestate: return @"savestates";
        case RPCS3PickerModeInsertDisc: return @"disc/inserted";
        default: return @"imports";
    }
}

- (NSURL *)copySource:(NSURL *)source intoFolder:(NSString *)folder error:(NSError **)error {
    NSString *root = self.dataRoot;
    if (!root.length) {
        if (error) *error = [NSError errorWithDomain:@"RPCS3IOS" code:1 userInfo:@{NSLocalizedDescriptionKey:@"RPCS3 data root is unavailable."}];
        return nil;
    }
    NSString *directory = [root stringByAppendingPathComponent:folder];
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *name = source.lastPathComponent.length ? source.lastPathComponent : NSUUID.UUID.UUIDString;
    NSURL *destination = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:name]];
    if ([NSFileManager.defaultManager fileExistsAtPath:destination.path]) {
        destination = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@", NSUUID.UUID.UUIDString, name]]];
    }
    BOOL scoped = [source startAccessingSecurityScopedResource];
    BOOL copied = [NSFileManager.defaultManager copyItemAtURL:source toURL:destination error:error];
    if (scoped) [source stopAccessingSecurityScopedResource];
    return copied ? destination : nil;
}

- (void)bootPath:(NSString *)path title:(NSString *)title {
    if (!path.length || ![NSFileManager.defaultManager fileExistsAtPath:path]) {
        [self showTitle:title message:@"The required executable was not found."];
        return;
    }
    int result = rpcs3_ios_core_boot_elf(path.fileSystemRepresentation);
    RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    NSString *detail = diagnostics.message ? ([NSString stringWithUTF8String:diagnostics.message] ?: @"") : @"";
    [self showTitle:title message:[NSString stringWithFormat:@"Core bridge result: %@\n\n%@", result ? @"accepted" : @"failed", detail.length ? detail : @"No diagnostic message."]];
}

- (void)bootVSH {
    NSString *root = self.dataRoot;
    NSArray<NSString *> *candidates = @[
        [root stringByAppendingPathComponent:@"dev_flash/vsh/module/vsh.self"],
        [root stringByAppendingPathComponent:@"firmware/dev_flash/vsh/module/vsh.self"],
        [root stringByAppendingPathComponent:@"imports/dev_flash/vsh/module/vsh.self"]
    ];
    for (NSString *candidate in candidates) {
        if ([NSFileManager.defaultManager fileExistsAtPath:candidate]) {
            [self bootPath:candidate title:@"Boot VSH/XMB"];
            return;
        }
    }
    [self showTitle:@"Boot VSH/XMB" message:@"vsh.self was not found under the RPCS3 dev_flash tree. Install or extract PS3 firmware first."];
}

- (void)openURLString:(NSString *)value {
    NSURL *url = [NSURL URLWithString:value];
    if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)handleActionIdentifier:(NSString *)identifier {
    NSDictionary<NSString *, NSArray<NSString *> *> *routes = @{
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
        @"actionBasic_Mouse": @[@"basic_mouse_settings_dialog.ui", @""],
        @"actionRaw_Mouse": @[@"raw_mouse_settings_dialog.ui", @""],
        @"confCamerasAct": @[@"camera_settings_dialog.ui", @""],
        @"actionPS_Move_Tracker": @[@"ps_move_tracker_dialog.ui", @""],
        @"confShortcutsAct": @[@"shortcut_dialog.ui", @""],
        @"confAutopauseManagerAct": @[@"auto_pause_settings_dialog.ui", @""],
        @"confVFSDialogAct": @[@"vfs_dialog.ui", @""],
        @"toolsVfsDialogAct": @[@"vfs_tool_dialog.ui", @""],
        @"confRPCNAct": @[@"rpcn_settings_dialog.ui", @""],
        @"confIPCAct": @[@"ipc_settings_dialog.ui", @""],
        @"confSavedataManagerAct": @[@"save_data_dialog.ui", @""],
        @"actionManage_Trophy_Data": @[@"trophy_manager_dialog.ui", @""],
        @"actionManage_Savestates": @[@"savestate_manager_dialog.ui", @""],
        @"actionManage_Cheats": @[@"cheat_manager_dialog.ui", @""],
        @"actionManage_Game_Patches": @[@"patch_manager_dialog.ui", @""],
        @"actionManage_Screenshots": @[@"screenshot_manager_dialog.ui", @""],
        @"patchCreatorAct": @[@"patch_creator_dialog.ui", @""],
        @"actionMusic_Player": @[@"music_player_dialog.ui", @""],
        @"toolsSystemCommandsAct": @[@"system_cmd_dialog.ui", @""],
        @"toolsmemory_viewerAct": @[@"memory_viewer.ui", @""],
        @"toolskernel_explorerAct": @[@"kernel_explorer.ui", @""],
        @"toolsRsxDebuggerAct": @[@"rsx_debugger.ui", @""],
        @"aboutAct": @[@"about_dialog.ui", @""]
    };
    NSArray<NSString *> *route = routes[identifier];
    if (route) { [self pushDocument:route[0] preferredPage:route[1]]; return; }

    if ([identifier isEqualToString:@"bootGameAct"] || [identifier isEqualToString:@"addGamesAct"] || [identifier isEqualToString:@"addIsoGamesAct"]) {
        [self presentPickerMode:RPCS3PickerModeImportGame identifier:identifier multiple:YES folders:YES]; return;
    }
    if ([identifier isEqualToString:@"bootElfAct"] || [identifier isEqualToString:@"bootTestAct"]) {
        [self presentPickerMode:RPCS3PickerModeBootExecutable identifier:identifier multiple:NO folders:NO]; return;
    }
    if ([identifier isEqualToString:@"bootIsoAct"]) {
        [self presentPickerMode:RPCS3PickerModeImportISO identifier:identifier multiple:NO folders:NO]; return;
    }
    if ([identifier isEqualToString:@"bootVSHAct"]) { [self bootVSH]; return; }
    if ([identifier isEqualToString:@"bootInstallPkgAct"]) {
        [self presentPickerMode:RPCS3PickerModeInstallPackage identifier:identifier multiple:YES folders:NO]; return;
    }
    if ([identifier isEqualToString:@"bootInstallPupAct"]) {
        [self presentPickerMode:RPCS3PickerModeInstallFirmware identifier:identifier multiple:NO folders:NO]; return;
    }
    if ([identifier isEqualToString:@"actionManage_RAP_Licenses"]) {
        [self presentPickerMode:RPCS3PickerModeImportLicense identifier:identifier multiple:YES folders:NO]; return;
    }
    if ([identifier isEqualToString:@"bootSavestateAct"]) {
        [self presentPickerMode:RPCS3PickerModeBootSavestate identifier:identifier multiple:NO folders:NO]; return;
    }
    if ([identifier isEqualToString:@"insertDiscAct"]) {
        [self presentPickerMode:RPCS3PickerModeInsertDisc identifier:identifier multiple:NO folders:YES]; return;
    }
    if ([identifier isEqualToString:@"ejectDiscAct"]) {
        NSString *inserted = [self.dataRoot stringByAppendingPathComponent:@"disc/inserted"];
        [NSFileManager.defaultManager removeItemAtPath:inserted error:nil];
        [self showTitle:@"Eject Disc" message:@"The staged disc was removed."]; return;
    }
    if ([identifier isEqualToString:@"refreshGameListAct"] || [identifier isEqualToString:@"cleanUpGameListAct"]) {
        if (self.reloadHandler) self.reloadHandler(); return;
    }
    if ([identifier isEqualToString:@"sysStopAct"]) { rpcs3_ios_core_stop(); return; }
    if ([identifier isEqualToString:@"actionLog_Viewer"]) {
        [self.owner.navigationController pushViewController:[[RPCS3UtilitiesController alloc] initWithStyle:UITableViewStyleInsetGrouped] animated:YES]; return;
    }
    if ([identifier isEqualToString:@"setListModeAct"] || [identifier isEqualToString:@"setGridModeAct"]) {
        [NSUserDefaults.standardUserDefaults setObject:identifier forKey:@"RPCS3IOS.GameListViewAction"]; if (self.reloadHandler) self.reloadHandler(); return;
    }
    if ([identifier hasPrefix:@"setIconSize"] || [identifier isEqualToString:@"actionPreferGameDataIcons"] || [identifier isEqualToString:@"showCustomIconsAct"] || [identifier isEqualToString:@"playHoverGifsAct"]) {
        [NSUserDefaults.standardUserDefaults setObject:identifier forKey:@"RPCS3IOS.GameListIconAction"]; if (self.reloadHandler) self.reloadHandler(); return;
    }
    if ([identifier isEqualToString:@"quickstartAct"]) { [self openURLString:@"https://rpcs3.net/quickstart"]; return; }
    if ([identifier isEqualToString:@"compatibilityAct"]) { [self openURLString:@"https://rpcs3.net/compatibility"]; return; }
    if ([identifier isEqualToString:@"reportIssueAct"]) { [self openURLString:@"https://github.com/RPCS3/rpcs3/issues"]; return; }

    NSString *message = [NSString stringWithFormat:@"The original RPCS3 action %@ is preserved, but its real Emu.System or desktop-tool backend is not connected to the iOS bridge yet.", identifier];
    [self showTitle:identifier message:message];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    (void)controller;
    RPCS3PickerMode mode = self.pickerMode;
    self.pickerMode = RPCS3PickerModeNone;
    NSMutableArray<NSURL *> *destinations = [NSMutableArray array];
    NSError *lastError = nil;
    for (NSURL *source in urls) {
        NSError *copyError = nil;
        NSURL *destination = [self copySource:source intoFolder:[self folderForMode:mode] error:&copyError];
        if (destination) [destinations addObject:destination];
        else lastError = copyError;
    }

    if (mode == RPCS3PickerModeBootExecutable && destinations.firstObject) {
        [self bootPath:destinations.firstObject.path title:@"Boot SELF/ELF"];
    } else if (destinations.count) {
        if (self.reloadHandler && (mode == RPCS3PickerModeImportGame || mode == RPCS3PickerModeImportISO)) self.reloadHandler();
        NSString *note = @"Files copied into the RPCS3 data tree.";
        if (mode == RPCS3PickerModeInstallPackage || mode == RPCS3PickerModeInstallFirmware) note = @"Files are staged in the RPCS3 data tree. The real upstream installer backend still must be connected before extraction or installation occurs.";
        if (mode == RPCS3PickerModeBootSavestate) note = @"Savestate copied. Real savestate restore remains blocked on the upstream runtime bridge.";
        [self showTitle:self.pendingIdentifier.length ? self.pendingIdentifier : @"RPCS3" message:[NSString stringWithFormat:@"%@\n\nImported: %lu", note, (unsigned long)destinations.count]];
    } else if (lastError) {
        [self showTitle:@"Import Failed" message:lastError.localizedDescription ?: @"The selected file could not be copied."];
    }
    self.pendingIdentifier = @"";
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    (void)controller;
    self.pickerMode = RPCS3PickerModeNone;
    self.pendingIdentifier = @"";
}

@end
