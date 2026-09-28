#import "RPCS3LaunchSession.h"
#import "RPCS3GameLibrary.h"
#import "RPCS3CoreBridge.h"

static NSString *SessionLogPath(void) {
    RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics();
    NSString *root = d.data_path ? ([NSString stringWithUTF8String:d.data_path] ?: @"") : @"";
    return [[root stringByAppendingPathComponent:@"logs"] stringByAppendingPathComponent:@"launch-sessions.log"];
}

static NSString *CapabilityLabel(RPCS3IOSCoreCapabilityLevel level) {
    switch (level) {
        case RPCS3IOSCoreCapabilityProbeOnly: return @"probe-only";
        case RPCS3IOSCoreCapabilityPartialUpstream: return @"partial-upstream";
        case RPCS3IOSCoreCapabilityExecutionCapable: return @"execution-capable";
    }
    return @"unknown";
}

static void AppendSessionLine(NSString *line) {
    NSString *path = SessionLogPath();
    if (!path.length) return;
    [NSFileManager.defaultManager createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *record = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, line ?: @""];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [record writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return;
    }
    [handle seekToEndOfFile];
    [handle writeData:[record dataUsingEncoding:NSUTF8StringEncoding]];
    [handle closeFile];
}

@interface RPCS3LaunchSessionController ()
@property(nonatomic,strong) RPCS3GameEntry *entry;
@property(nonatomic,strong) UILabel *stateLabel;
@property(nonatomic,strong) UITextView *detailsView;
@property(nonatomic,strong) UIButton *launchButton;
@end

@implementation RPCS3LaunchSessionController
- (instancetype)initWithEntry:(RPCS3GameEntry *)entry { if ((self=[super init])) _entry=entry; return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Launch Session";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    RPCS3IOSCoreDiagnostics diagnostics = rpcs3_ios_core_diagnostics();
    UIImageView *art=[[UIImageView alloc] init]; art.translatesAutoresizingMaskIntoConstraints=NO; art.contentMode=UIViewContentModeScaleAspectFit; art.layer.cornerRadius=14; art.clipsToBounds=YES; art.backgroundColor=UIColor.secondarySystemBackgroundColor; art.image=self.entry.iconURL?[UIImage imageWithContentsOfFile:self.entry.iconURL.path]:[UIImage systemImageNamed:@"gamecontroller.fill"];
    UILabel *title=[[UILabel alloc] init]; title.translatesAutoresizingMaskIntoConstraints=NO; title.font=[UIFont preferredFontForTextStyle:UIFontTextStyleTitle2]; title.adjustsFontForContentSizeCategory=YES; title.numberOfLines=0; title.text=self.entry.title;
    self.stateLabel=[[UILabel alloc] init]; self.stateLabel.translatesAutoresizingMaskIntoConstraints=NO; self.stateLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; self.stateLabel.text=@"Loader validation available";
    self.detailsView=[[UITextView alloc] init]; self.detailsView.translatesAutoresizingMaskIntoConstraints=NO; self.detailsView.editable=NO; self.detailsView.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; self.detailsView.backgroundColor=UIColor.secondarySystemBackgroundColor; self.detailsView.layer.cornerRadius=12; self.detailsView.text=[NSString stringWithFormat:@"Title ID: %@\nBoot path: %@\nCore classification: %@\nPinned RPCS3: %s\n\nThis action validates or reconstructs a supported executable. It does not start Emu.System or execute PPU/SPU instructions.",self.entry.titleID.length?self.entry.titleID:@"Unknown",self.entry.bootURL.path?:@"No executable",CapabilityLabel(diagnostics.capability_level),diagnostics.upstream_revision?:"unknown"];
    self.launchButton=[UIButton buttonWithType:UIButtonTypeSystem]; self.launchButton.translatesAutoresizingMaskIntoConstraints=NO; self.launchButton.configuration=[UIButtonConfiguration filledButtonConfiguration]; [self.launchButton setTitle:@"Validate Boot File" forState:UIControlStateNormal]; [self.launchButton addTarget:self action:@selector(runLaunch) forControlEvents:UIControlEventTouchUpInside]; self.launchButton.enabled=self.entry.bootURL!=nil;
    UIStackView *stack=[[UIStackView alloc] initWithArrangedSubviews:@[art,title,self.stateLabel,self.detailsView,self.launchButton]]; stack.translatesAutoresizingMaskIntoConstraints=NO; stack.axis=UILayoutConstraintAxisVertical; stack.spacing=14;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],[stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],[art.heightAnchor constraintEqualToAnchor:art.widthAnchor multiplier:0.45],[art.heightAnchor constraintLessThanOrEqualToConstant:260],[self.detailsView.heightAnchor constraintGreaterThanOrEqualToConstant:180]]];
}
- (void)runLaunch {
    if (!self.entry.bootURL) return;
    self.launchButton.enabled=NO; self.stateLabel.text=@"Validating executable…";
    NSString *start=[NSString stringWithFormat:@"BEGIN title=%@ id=%@ path=%@",self.entry.title,self.entry.titleID,self.entry.bootURL.path]; AppendSessionLine(start);
    int ready=rpcs3_ios_core_boot_elf(self.entry.bootURL.path.fileSystemRepresentation);
    RPCS3IOSCoreDiagnostics d=rpcs3_ios_core_diagnostics();
    NSString *message=d.message?([NSString stringWithUTF8String:d.message]?:@"Invalid loader message"):@"No loader message";
    self.stateLabel.text=ready?@"Executable validated":@"Validation failed";
    self.detailsView.text=[NSString stringWithFormat:@"Result: %@\nClassification: %@\nPinned RPCS3: %s\nDirect upstream sources: %d\nCore state: %d\nPlatform initialized: %@\nPPU interpreter linked: %@\nSPU interpreter linked: %@\nJIT linked: %@\nRSX renderer linked: %@\n\n%@",ready?@"validated":@"failed",CapabilityLabel(d.capability_level),d.upstream_revision?:"unknown",d.upstream_source_count,d.state,d.platform_initialized?@"yes":@"no",d.ppu_interpreter_available?@"yes":@"no",d.spu_interpreter_available?@"yes":@"no",d.jit_available?@"yes":@"no",d.renderer_available?@"yes":@"no",message];
    AppendSessionLine([NSString stringWithFormat:@"END result=%@ classification=%@ message=%@",ready?@"validated":@"failed",CapabilityLabel(d.capability_level),message]);
    self.launchButton.enabled=YES;
    UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification,self.stateLabel.text);
}
@end
