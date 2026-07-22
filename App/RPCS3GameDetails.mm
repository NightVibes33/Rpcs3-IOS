#import "RPCS3GameDetails.h"
#import "RPCS3GameLibrary.h"
#import "RPCS3CoreBridge.h"

@interface RPCS3GameDetailsController ()
@property(nonatomic,strong) RPCS3GameEntry *entry;
@property(nonatomic,strong) UILabel *statusLabel;
@end

@implementation RPCS3GameDetailsController
- (instancetype)initWithEntry:(RPCS3GameEntry *)entry { if ((self=[super init])) _entry=entry; return self; }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.entry.title;
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UIImageView *art = [[UIImageView alloc] init]; art.translatesAutoresizingMaskIntoConstraints = NO; art.contentMode = UIViewContentModeScaleAspectFit; art.layer.cornerRadius = 14; art.clipsToBounds = YES; art.backgroundColor = UIColor.secondarySystemBackgroundColor; art.image = self.entry.iconURL ? [UIImage imageWithContentsOfFile:self.entry.iconURL.path] : [UIImage systemImageNamed:@"gamecontroller.fill"];
    UILabel *title = [[UILabel alloc] init]; title.translatesAutoresizingMaskIntoConstraints = NO; title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle1]; title.adjustsFontForContentSizeCategory = YES; title.numberOfLines = 0; title.text = self.entry.title;
    UILabel *meta = [[UILabel alloc] init]; meta.translatesAutoresizingMaskIntoConstraints = NO; meta.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody]; meta.textColor = UIColor.secondaryLabelColor; meta.numberOfLines = 0; meta.text = [NSString stringWithFormat:@"Title ID: %@\nCategory: %@\nVersion: %@", self.entry.titleID.length?self.entry.titleID:@"Unknown", self.entry.category.length?self.entry.category:@"Unknown", self.entry.version.length?self.entry.version:@"Unknown"];
    UIButton *boot = [UIButton buttonWithType:UIButtonTypeSystem]; boot.translatesAutoresizingMaskIntoConstraints = NO; [boot setTitle:@"Boot" forState:UIControlStateNormal]; boot.titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline]; boot.configuration = [UIButtonConfiguration filledButtonConfiguration]; [boot addTarget:self action:@selector(bootGame) forControlEvents:UIControlEventTouchUpInside]; boot.enabled = self.entry.bootURL != nil;
    self.statusLabel = [[UILabel alloc] init]; self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO; self.statusLabel.numberOfLines = 0; self.statusLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote]; self.statusLabel.textColor = UIColor.secondaryLabelColor; self.statusLabel.text = self.entry.bootURL ? self.entry.bootURL.path : @"No boot executable found";
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[art,title,meta,boot,self.statusLabel]]; stack.translatesAutoresizingMaskIntoConstraints = NO; stack.axis = UILayoutConstraintAxisVertical; stack.spacing = 16;
    [self.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],[stack.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:20],[stack.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-20],[art.heightAnchor constraintLessThanOrEqualToConstant:320],[art.heightAnchor constraintEqualToAnchor:art.widthAnchor multiplier:0.56]]];
}
- (void)bootGame {
    if (!self.entry.bootURL) return;
    int ready = rpcs3_ios_core_boot_elf(self.entry.bootURL.path.fileSystemRepresentation);
    RPCS3IOSCoreDiagnostics d = rpcs3_ios_core_diagnostics();
    self.statusLabel.text = d.message ? ([NSString stringWithUTF8String:d.message] ?: @"Invalid loader message") : @"No loader message";
    if (!ready) UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, self.statusLabel.text);
}
@end
