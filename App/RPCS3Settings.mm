#import "RPCS3Settings.h"
#import "RPCS3ConfigStore.h"

static NSString *const RPCS3SettingsDefaultsKey = @"RPCS3IOS.Settings";

static NSMutableDictionary *LoadSettings(void) {
    NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:RPCS3SettingsDefaultsKey];
    NSMutableDictionary *values = saved ? [saved mutableCopy] : [NSMutableDictionary dictionary];
    NSDictionary *defaults = @{
        @"ppu_decoder": @"Interpreter", @"spu_decoder": @"Interpreter", @"renderer": @"Metal",
        @"resolution_scale": @100, @"vsync": @YES, @"audio_backend": @"AudioUnit",
        @"audio_buffering": @YES, @"network_status": @"Disconnected", @"language": @"English",
        @"confirm_exit": @YES, @"show_trophy_popups": @YES, @"preferred_fps": @60,
        @"pad_handler": @"iOS Game Controller", @"touch_overlay": @YES, @"motion_controls": @YES
    };
    [defaults enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) { (void)stop; if (!values[key]) values[key] = value; }];
    return values;
}

static void SaveSettings(NSDictionary *values) {
    [NSUserDefaults.standardUserDefaults setObject:values forKey:RPCS3SettingsDefaultsKey];
    RPCS3IOSWriteConfig(values, nil);
}

@interface RPCS3OptionController : UITableViewController
@property(nonatomic,copy) NSString *settingKey;
@property(nonatomic,copy) NSArray<NSString *> *options;
@property(nonatomic,strong) NSMutableDictionary *values;
@end

@implementation RPCS3OptionController
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.options.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"option"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"option"];
    NSString *option=self.options[indexPath.row]; cell.textLabel.text=option; cell.accessoryType=[self.values[self.settingKey] isEqual:option]?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; self.values[self.settingKey]=self.options[indexPath.row]; SaveSettings(self.values); [tableView reloadData]; }
@end

@interface RPCS3SettingsController ()
@property(nonatomic,strong) NSMutableDictionary *values;
@property(nonatomic,copy) NSArray<NSArray<NSDictionary *> *> *sections;
@end

@implementation RPCS3SettingsController
- (void)viewDidLoad {
    [super viewDidLoad]; self.title=@"Settings"; self.values=LoadSettings(); SaveSettings(self.values);
    self.sections=@[
        @[@{@"title":@"PPU Decoder",@"key":@"ppu_decoder",@"type":@"option",@"options":@[@"Interpreter",@"LLVM Recompiler"]},@{@"title":@"SPU Decoder",@"key":@"spu_decoder",@"type":@"option",@"options":@[@"Interpreter",@"ASMJIT",@"LLVM Recompiler"]}],
        @[@{@"title":@"Renderer",@"key":@"renderer",@"type":@"option",@"options":@[@"Metal"]},@{@"title":@"Resolution Scale",@"key":@"resolution_scale",@"type":@"stepper"},@{@"title":@"VSync",@"key":@"vsync",@"type":@"switch"},@{@"title":@"Preferred Frame Rate",@"key":@"preferred_fps",@"type":@"option",@"options":@[@"30",@"60",@"120"]}],
        @[@{@"title":@"Audio Backend",@"key":@"audio_backend",@"type":@"option",@"options":@[@"AudioUnit",@"Null"]},@{@"title":@"Audio Buffering",@"key":@"audio_buffering",@"type":@"switch"}],
        @[@{@"title":@"Network Status",@"key":@"network_status",@"type":@"option",@"options":@[@"Disconnected",@"Connected"]},@{@"title":@"System Language",@"key":@"language",@"type":@"option",@"options":@[@"English",@"Japanese",@"French",@"German",@"Spanish"]}],
        @[@{@"title":@"Confirm Exit",@"key":@"confirm_exit",@"type":@"switch"},@{@"title":@"Show Trophy Popups",@"key":@"show_trophy_popups",@"type":@"switch"}]
    ];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return self.sections.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; return @[@"CPU",@"GPU",@"Audio",@"Network & System",@"Advanced"][section]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return self.sections[section].count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item=self.sections[indexPath.section][indexPath.row]; NSString *type=item[@"type"];
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"setting"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"setting"];
    cell.textLabel.text=item[@"title"]; cell.accessoryView=nil; cell.accessoryType=UITableViewCellAccessoryNone; cell.detailTextLabel.text=@"";
    if([type isEqual:@"switch"]){UISwitch *toggle=[[UISwitch alloc] init];toggle.on=[self.values[item[@"key"]] boolValue];toggle.accessibilityIdentifier=item[@"key"];[toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;}
    else if([type isEqual:@"stepper"]){UIStepper *stepper=[[UIStepper alloc] init];stepper.minimumValue=50;stepper.maximumValue=300;stepper.stepValue=25;stepper.value=[self.values[item[@"key"]] doubleValue];stepper.accessibilityIdentifier=item[@"key"];[stepper addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=stepper;cell.detailTextLabel.text=[NSString stringWithFormat:@"%@%%",self.values[item[@"key"]]];}
    else{cell.detailTextLabel.text=[self.values[item[@"key"]] description];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;} return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; NSDictionary *item=self.sections[indexPath.section][indexPath.row]; if(![item[@"type"] isEqual:@"option"])return; RPCS3OptionController *options=[[RPCS3OptionController alloc] initWithStyle:UITableViewStyleInsetGrouped];options.title=item[@"title"];options.settingKey=item[@"key"];NSMutableArray *values=[NSMutableArray array];for(id option in item[@"options"])[values addObject:[option description]];options.options=values;options.values=self.values;[self.navigationController pushViewController:options animated:YES]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)toggleChanged:(UISwitch *)sender { self.values[sender.accessibilityIdentifier]=@(sender.on); SaveSettings(self.values); }
- (void)stepperChanged:(UIStepper *)sender { self.values[sender.accessibilityIdentifier]=@((NSInteger)sender.value); SaveSettings(self.values); [self.tableView reloadData]; }
@end

@interface RPCS3PadsController () @property(nonatomic,strong) NSMutableDictionary *values; @end
@implementation RPCS3PadsController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"Pads"; self.values=LoadSettings(); SaveSettings(self.values); }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { (void)tableView; return section==0?@"Player 1":@"Touch Controls"; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return section==0?1:2; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath { UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"pad"]?:[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"pad"]; if(indexPath.section==0){cell.textLabel.text=@"Handler";cell.detailTextLabel.text=self.values[@"pad_handler"];cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;cell.accessoryView=nil;}else{NSString *key=indexPath.row==0?@"touch_overlay":@"motion_controls";cell.textLabel.text=indexPath.row==0?@"On-Screen Controls":@"Motion Controls";UISwitch *toggle=[[UISwitch alloc] init];toggle.on=[self.values[key] boolValue];toggle.accessibilityIdentifier=key;[toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;cell.accessoryType=UITableViewCellAccessoryNone;cell.detailTextLabel.text=@"";}return cell; }
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES];if(indexPath.section!=0)return;RPCS3OptionController *options=[[RPCS3OptionController alloc] initWithStyle:UITableViewStyleInsetGrouped];options.title=@"Pad Handler";options.settingKey=@"pad_handler";options.options=@[@"iOS Game Controller",@"Touch Overlay",@"Null"];options.values=self.values;[self.navigationController pushViewController:options animated:YES]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated]; [self.tableView reloadData]; }
- (void)toggleChanged:(UISwitch *)sender { self.values[sender.accessibilityIdentifier]=@(sender.on); SaveSettings(self.values); }
@end
