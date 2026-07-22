#import "RPCS3UpstreamMenuModel.h"

static UIAction *RPCS3Action(NSString *title, NSString *identifier, NSString *symbol, RPCS3UpstreamMenuActionHandler handler) {
    UIAction *action = [UIAction actionWithTitle:title image:symbol.length ? [UIImage systemImageNamed:symbol] : nil identifier:identifier handler:^(__kindof UIAction *sender) {
        (void)sender;
        if (handler) handler(identifier);
    }];
    return action;
}

static UIMenu *RPCS3Menu(NSString *title, NSArray<UIMenuElement *> *children) {
    return [UIMenu menuWithTitle:title children:children];
}

UIMenu *RPCS3CreateUpstreamMainMenu(RPCS3UpstreamMenuActionHandler handler) {
    UIMenu *bootElf = RPCS3Menu(@"Boot (S)Elf", @[
        RPCS3Action(@"Boot SELF/ELF", @"bootElfAct", @"doc.badge.play", handler),
        RPCS3Action(@"Boot Test", @"bootTestAct", @"testtube.2", handler)
    ]);
    UIMenu *file = RPCS3Menu(@"File", @[
        RPCS3Action(@"Boot Game", @"bootGameAct", @"folder", handler),
        RPCS3Action(@"Boot ISO", @"bootIsoAct", @"opticaldisc", handler),
        RPCS3Action(@"Boot VSH/XMB", @"bootVSHAct", @"rectangle.3.group", handler),
        bootElf,
        RPCS3Action(@"Boot Savestate", @"bootSavestateAct", @"clock.arrow.circlepath", handler),
        RPCS3Action(@"Add Games", @"addGamesAct", @"plus.rectangle.on.folder", handler),
        RPCS3Action(@"Add ISO Games", @"addIsoGamesAct", @"plus.circle", handler),
        RPCS3Action(@"Install Packages/Raps/Edats", @"bootInstallPkgAct", @"shippingbox", handler),
        RPCS3Action(@"Install Firmware", @"bootInstallPupAct", @"square.and.arrow.down", handler),
        RPCS3Action(@"Clean Up Game List", @"cleanUpGameListAct", @"sparkles", handler),
        RPCS3Action(@"Exit and Save Log", @"exitAndSaveLogAct", @"doc.text", handler)
    ]);

    UIMenu *emulation = RPCS3Menu(@"Emulation", @[
        RPCS3Action(@"Pause/Resume", @"sysPauseAct", @"pause.fill", handler),
        RPCS3Action(@"Stop", @"sysStopAct", @"stop.fill", handler),
        RPCS3Action(@"Reboot", @"sysRebootAct", @"arrow.clockwise", handler),
        RPCS3Action(@"Insert Disc", @"insertDiscAct", @"opticaldiscdrive", handler),
        RPCS3Action(@"Eject Disc", @"ejectDiscAct", @"eject.fill", handler)
    ]);

    UIMenu *devices = RPCS3Menu(@"Devices", @[
        RPCS3Action(@"Pads", @"confPadsAct", @"gamecontroller", handler),
        RPCS3Action(@"Mice", @"actionBasic_Mouse", @"computermouse", handler),
        RPCS3Action(@"Cameras", @"confCamerasAct", @"camera", handler),
        RPCS3Action(@"PS Move Tracker", @"actionPS_Move_Tracker", @"move.3d", handler)
    ]);
    UIMenu *configuration = RPCS3Menu(@"Configuration", @[
        RPCS3Action(@"CPU", @"confCPUAct", @"cpu", handler),
        RPCS3Action(@"GPU", @"confGPUAct", @"display", handler),
        RPCS3Action(@"Audio", @"confAudioAct", @"speaker.wave.2", handler),
        RPCS3Action(@"I/O", @"confIOAct", @"cable.connector", handler),
        RPCS3Action(@"System", @"confSystemAct", @"gearshape.2", handler),
        RPCS3Action(@"Network", @"confNetwrkAct", @"network", handler),
        RPCS3Action(@"Advanced", @"confAdvAct", @"slider.horizontal.3", handler),
        RPCS3Action(@"Emulator", @"confEmuAct", @"memorychip", handler),
        RPCS3Action(@"GUI", @"confGuiAct", @"rectangle.on.rectangle", handler),
        devices,
        RPCS3Action(@"Shortcuts", @"confShortcutsAct", @"keyboard", handler),
        RPCS3Action(@"Manage Sound Effects", @"actionManage_SoundEffects", @"waveform", handler),
        RPCS3Action(@"Autopause Manager", @"confAutopauseManagerAct", @"pause.circle", handler)
    ]);

    UIMenu *networkServices = RPCS3Menu(@"Network Services", @[
        RPCS3Action(@"RPCN", @"confRPCNAct", @"person.2.wave.2", handler),
        RPCS3Action(@"Clans", @"confClansAct", @"person.3", handler),
        RPCS3Action(@"IPC", @"confIPCAct", @"arrow.left.arrow.right", handler)
    ]);
    UIMenu *manage = RPCS3Menu(@"Manage", @[
        RPCS3Action(@"Virtual File System", @"confVFSDialogAct", @"externaldrive", handler),
        RPCS3Action(@"Users", @"actionManage_Users", @"person.crop.circle", handler),
        networkServices,
        RPCS3Action(@"RAP Licenses", @"actionManage_RAP_Licenses", @"key", handler),
        RPCS3Action(@"Save Data", @"confSavedataManagerAct", @"internaldrive", handler),
        RPCS3Action(@"Trophy Data", @"actionManage_Trophy_Data", @"trophy", handler),
        RPCS3Action(@"Savestates", @"actionManage_Savestates", @"clock", handler),
        RPCS3Action(@"Cheats", @"actionManage_Cheats", @"wand.and.stars", handler),
        RPCS3Action(@"Game Patches", @"actionManage_Game_Patches", @"bandage", handler),
        RPCS3Action(@"Screenshots", @"actionManage_Screenshots", @"photo.on.rectangle", handler)
    ]);

    UIMenu *utilities = RPCS3Menu(@"Utilities", @[
        RPCS3Action(@"Log Viewer", @"actionLog_Viewer", @"doc.text.magnifyingglass", handler),
        RPCS3Action(@"Check Configuration", @"toolsCheckConfigAct", @"checkmark.shield", handler),
        RPCS3Action(@"VFS Explorer", @"toolsVfsDialogAct", @"folder.badge.gearshape", handler),
        RPCS3Action(@"Patch Creator", @"patchCreatorAct", @"hammer", handler),
        RPCS3Action(@"Music Player", @"actionMusic_Player", @"music.note", handler),
        RPCS3Action(@"Decrypt SPRX Libraries", @"toolsDecryptSprxLibsAct", @"lock.open", handler),
        RPCS3Action(@"Extract MSELF", @"toolsExtractMSELFAct", @"archivebox", handler),
        RPCS3Action(@"Extract PUP", @"toolsExtractPUPAct", @"archivebox", handler),
        RPCS3Action(@"Extract TAR", @"toolsExtractTARAct", @"archivebox", handler),
        RPCS3Action(@"System Commands", @"toolsSystemCommandsAct", @"terminal", handler),
        RPCS3Action(@"Memory Viewer", @"toolsmemory_viewerAct", @"memorychip", handler),
        RPCS3Action(@"Kernel Explorer", @"toolskernel_explorerAct", @"shippingbox.and.arrow.backward", handler),
        RPCS3Action(@"RSX Debugger", @"toolsRsxDebuggerAct", @"ladybug", handler),
        RPCS3Action(@"Create RSX Capture", @"actionCreate_RSX_Capture", @"record.circle", handler),
        RPCS3Action(@"Open RSX Capture", @"actionopen_rsx_capture", @"folder", handler),
        RPCS3Action(@"Create Savestate", @"actionCreate_Savestate", @"square.and.arrow.down", handler)
    ]);

    UIMenu *view = RPCS3Menu(@"View", @[
        RPCS3Action(@"List Mode", @"setListModeAct", @"list.bullet", handler),
        RPCS3Action(@"Grid Mode", @"setGridModeAct", @"square.grid.2x2", handler),
        RPCS3Action(@"Tiny Icons", @"setIconSizeTinyAct", @"square.grid.4x3.fill", handler),
        RPCS3Action(@"Small Icons", @"setIconSizeSmallAct", @"square.grid.3x3.fill", handler),
        RPCS3Action(@"Medium Icons", @"setIconSizeMediumAct", @"square.grid.2x2.fill", handler),
        RPCS3Action(@"Large Icons", @"setIconSizeLargeAct", @"square.fill", handler),
        RPCS3Action(@"Refresh", @"refreshGameListAct", @"arrow.clockwise", handler)
    ]);

    UIMenu *help = RPCS3Menu(@"Help", @[
        RPCS3Action(@"About RPCS3", @"aboutAct", @"info.circle", handler),
        RPCS3Action(@"Quickstart", @"quickstartAct", @"book", handler),
        RPCS3Action(@"Compatibility", @"compatibilityAct", @"checkmark.seal", handler),
        RPCS3Action(@"Report Issue", @"reportIssueAct", @"exclamationmark.bubble", handler)
    ]);

    return [UIMenu menuWithTitle:@"RPCS3" children:@[file, emulation, configuration, manage, utilities, view, help]];
}
