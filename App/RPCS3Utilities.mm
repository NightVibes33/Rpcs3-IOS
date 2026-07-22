#import "RPCS3Utilities.h"
#import "RPCS3ConfigStore.h"
#import "RPCS3CoreBridge.h"

static NSString *RPCS3CapabilityName(RPCS3IOSCoreCapabilityLevel level) {
    switch (level) {
        case RPCS3IOSCoreCapabilityProbeOnly: return @"Probe only";
        case RPCS3IOSCoreCapabilityPartialUpstream: return @"Partial upstream";
        case RPCS3IOSCoreCapabilityExecutionCapable: return @"Execution capable";
    }
    return @"Unknown";
}

@interface RPCS3TextViewerController : UIViewController
@property(nonatomic,copy) NSString *body;
@end
@implementation RPCS3TextViewerController
- (void)viewDidLoad { [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor; UITextView *text=[[UITextView alloc] init]; text.translatesAutoresizingMaskIntoConstraints=NO; text.editable=NO; text.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular]; text.text=self.body; [self.view addSubview:text]; [NSLayoutConstraint activateConstraints:@[[text.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[text.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[text.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[text.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]]; }
@end

@implementation RPCS3UtilitiesController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Utilities"; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; return section==0?@"RPCS3":@"Diagnostics"; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return section==0?2:1; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"utility"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"utility"];
    if(indexPath.section==0&&indexPath.row==0){cell.textLabel.text=@"View Config";cell.detailTextLabel.text=RPCS3IOSConfigPath();cell.imageView.image=[UIImage systemImageNamed:@"doc.text"];}
    else if(indexPath.section==0){cell.textLabel.text=@"View Latest Log";cell.detailTextLabel.text=@"RPCS3 runtime and loader output";cell.imageView.image=[UIImage systemImageNamed:@"text.alignleft"];}
    else{RPCS3IOSCoreDiagnostics d=rpcs3_ios_core_diagnostics();cell.textLabel.text=@"Core Status";cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ • %d upstream source%@",RPCS3CapabilityName(d.capability_level),d.upstream_source_count,d.upstream_source_count==1?@"":@"s"];cell.imageView.image=[UIImage systemImageNamed:@"waveform.path.ecg"];} cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES]; RPCS3TextViewerController *viewer=[RPCS3TextViewerController new];
    if(indexPath.section==0&&indexPath.row==0){viewer.title=@"config.yml";viewer.body=RPCS3IOSReadConfig();}
    else if(indexPath.section==0){viewer.title=@"Latest Log";viewer.body=RPCS3IOSReadLatestLog();}
    else{RPCS3IOSCoreDiagnostics d=rpcs3_ios_core_diagnostics();viewer.title=@"Core Status";viewer.body=[NSString stringWithFormat:@"Classification: %@\nBuild label: %s\nPinned upstream revision: %s\nDirect upstream sources: %d\nState: %d\nPlatform initialized: %@\nPPU interpreter linked: %@\nSPU interpreter linked: %@\nJIT linked: %@\nRSX renderer linked: %@\nData root: %s\n\n%s",RPCS3CapabilityName(d.capability_level),d.build_classification?:"unknown",d.upstream_revision?:"unknown",d.upstream_source_count,d.state,d.platform_initialized?@"yes":@"no",d.ppu_interpreter_available?@"yes":@"no",d.spu_interpreter_available?@"yes":@"no",d.jit_available?@"yes":@"no",d.renderer_available?@"yes":@"no",d.data_path?:"none",d.message?:"none"];}
    [self.navigationController pushViewController:viewer animated:YES];
}
@end
