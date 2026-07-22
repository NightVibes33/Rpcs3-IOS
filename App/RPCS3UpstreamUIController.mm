#import "RPCS3UpstreamUIController.h"

static NSString *S(id value) { return [value isKindOfClass:NSString.class] ? value : @""; }
static NSArray *A(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static NSDictionary *D(id value) { return [value isKindOfClass:NSDictionary.class] ? value : @{}; }

NSDictionary *RPCS3LoadBundledQtUIModel(void) {
    static NSDictionary *model;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"RPCS3QtUIModel" ofType:@"json"];
        NSData *data = path.length ? [NSData dataWithContentsOfFile:path] : nil;
        id json = data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if ([json isKindOfClass:NSDictionary.class]) model = json;
    });
    return model;
}

static UILabel *Label(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

static UIStackView *VStack(void) {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 10;
    return stack;
}

static UIView *BuildNode(NSDictionary *node, NSString *preferredPage);

@interface RPCS3QtPagesView : UIView
@property(nonatomic,strong) NSArray<NSDictionary *> *pages;
@property(nonatomic,strong) UISegmentedControl *segments;
@property(nonatomic,strong) UIView *content;
@property(nonatomic,copy) NSString *preferredPage;
@end

@implementation RPCS3QtPagesView
- (instancetype)initWithNode:(NSDictionary *)node preferredPage:(NSString *)preferredPage {
    if ((self = [super init])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.pages = A(node[@"children"]);
        self.preferredPage = preferredPage ?: @"";
        NSMutableArray *titles = [NSMutableArray array];
        __block NSInteger selected = 0;
        [self.pages enumerateObjectsUsingBlock:^(NSDictionary *page, NSUInteger index, BOOL *stop) {
            (void)stop;
            NSString *title = S(page[@"title"]);
            [titles addObject:title.length ? title : (S(page[@"name"]).length ? S(page[@"name"]) : [NSString stringWithFormat:@"Page %lu", (unsigned long)index + 1])];
            if (self.preferredPage.length && [S(page[@"name"]) isEqualToString:self.preferredPage]) selected = (NSInteger)index;
        }];

        self.segments = [[UISegmentedControl alloc] initWithItems:titles];
        self.segments.translatesAutoresizingMaskIntoConstraints = NO;
        self.segments.apportionsSegmentWidthsByContent = YES;
        self.segments.selectedSegmentIndex = titles.count ? selected : UISegmentedControlNoSegment;
        [self.segments addTarget:self action:@selector(selectPage:) forControlEvents:UIControlEventValueChanged];

        UIScrollView *tabs = [[UIScrollView alloc] init];
        tabs.translatesAutoresizingMaskIntoConstraints = NO;
        tabs.showsHorizontalScrollIndicator = NO;
        [tabs addSubview:self.segments];

        self.content = [[UIView alloc] init];
        self.content.translatesAutoresizingMaskIntoConstraints = NO;
        UIStackView *stack = VStack();
        [stack addArrangedSubview:tabs];
        [stack addArrangedSubview:self.content];
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [tabs.heightAnchor constraintEqualToConstant:40],
            [self.segments.topAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.topAnchor],
            [self.segments.leadingAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.leadingAnchor],
            [self.segments.trailingAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.trailingAnchor],
            [self.segments.bottomAnchor constraintEqualToAnchor:tabs.contentLayoutGuide.bottomAnchor],
            [self.segments.heightAnchor constraintEqualToAnchor:tabs.frameLayoutGuide.heightAnchor],
            [self.content.heightAnchor constraintGreaterThanOrEqualToConstant:60]
        ]];
        [self showPage:selected];
    }
    return self;
}
- (void)selectPage:(UISegmentedControl *)sender { [self showPage:sender.selectedSegmentIndex]; }
- (void)showPage:(NSInteger)index {
    [self.content.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    if (index < 0 || index >= (NSInteger)self.pages.count) return;
    UIView *page = BuildNode(self.pages[(NSUInteger)index], self.preferredPage);
    page.translatesAutoresizingMaskIntoConstraints = NO;
    [self.content addSubview:page];
    [NSLayoutConstraint activateConstraints:@[
        [page.topAnchor constraintEqualToAnchor:self.content.topAnchor],
        [page.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],
        [page.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],
        [page.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor]
    ]];
}
@end

static UIView *NamedRow(NSDictionary *node, UIView *control) {
    NSString *title = S(node[@"text"]);
    if (!title.length) title = S(node[@"title"]);
    NSString *name = S(node[@"name"]);
    if (!title.length) title = name;
    UIStackView *labels = VStack();
    labels.spacing = 2;
    [labels addArrangedSubview:Label(title.length ? title : @"RPCS3 option", [UIFont preferredFontForTextStyle:UIFontTextStyleBody], UIColor.labelColor)];
    if (name.length && ![name isEqualToString:title]) [labels addArrangedSubview:Label(name, [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular], UIColor.tertiaryLabelColor)];
    [labels setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:control ? @[labels, control] : @[labels]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    if (control) [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}

static UIView *Card(NSDictionary *node, NSArray<UIView *> *children) {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 12;
    UIStackView *stack = VStack();
    NSString *title = S(node[@"title"]);
    if (title.length) [stack addArrangedSubview:Label(title, [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline], UIColor.labelColor)];
    for (UIView *child in children) [stack addArrangedSubview:child];
    [card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]
    ]];
    return card;
}

static NSArray<UIView *> *BuildChildren(NSDictionary *node, NSString *preferredPage) {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *child in A(node[@"children"])) [result addObject:BuildNode(child, preferredPage)];
    return result;
}

static UIView *BuildNode(NSDictionary *node, NSString *preferredPage) {
    NSString *cls = S(node[@"class"]), *text = S(node[@"text"]), *name = S(node[@"name"]);
    if ([cls isEqualToString:@"QTabWidget"] || [cls isEqualToString:@"QToolBox"] || [cls isEqualToString:@"QStackedWidget"]) return [[RPCS3QtPagesView alloc] initWithNode:node preferredPage:preferredPage];
    if ([cls isEqualToString:@"QCheckBox"]) { UISwitch *v=[[UISwitch alloc] init]; v.on=[S(node[@"checked"]) isEqualToString:@"true"]; v.accessibilityIdentifier=name; return NamedRow(node,v); }
    if ([cls isEqualToString:@"QRadioButton"]) { UIButton *v=[UIButton buttonWithType:UIButtonTypeSystem]; [v setImage:[UIImage systemImageNamed:@"circle"] forState:UIControlStateNormal]; v.accessibilityIdentifier=name; return NamedRow(node,v); }
    if ([cls isEqualToString:@"QComboBox"]) {
        UIButton *v=[UIButton buttonWithType:UIButtonTypeSystem]; [v setTitle:@"Choose" forState:UIControlStateNormal];
        NSMutableArray *actions=[NSMutableArray array];
        for (NSString *item in A(node[@"items"])) [actions addObject:[UIAction actionWithTitle:item handler:^(__kindof UIAction *action){ [v setTitle:action.title forState:UIControlStateNormal]; }]];
        if (actions.count) { v.menu=[UIMenu menuWithChildren:actions]; v.showsMenuAsPrimaryAction=YES; }
        return NamedRow(node,v);
    }
    if ([cls isEqualToString:@"QSlider"]) { UISlider *v=[[UISlider alloc] init]; [v.widthAnchor constraintGreaterThanOrEqualToConstant:120].active=YES; return NamedRow(node,v); }
    if ([cls isEqualToString:@"QSpinBox"] || [cls isEqualToString:@"QDoubleSpinBox"]) return NamedRow(node,[[UIStepper alloc] init]);
    if ([cls isEqualToString:@"QPushButton"] || [cls isEqualToString:@"QToolButton"]) { UIButton *v=[UIButton buttonWithType:UIButtonTypeSystem]; v.configuration=[UIButtonConfiguration borderedButtonConfiguration]; [v setTitle:text.length?text:name forState:UIControlStateNormal]; v.accessibilityIdentifier=name; return v; }
    if ([cls isEqualToString:@"QLineEdit"]) { UITextField *v=[[UITextField alloc] init]; v.borderStyle=UITextBorderStyleRoundedRect; v.placeholder=S(node[@"placeholder"]); v.accessibilityIdentifier=name; return NamedRow(node,v); }
    if ([cls isEqualToString:@"QLabel"]) return text.length ? Label(text,[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote],UIColor.secondaryLabelColor) : [[UIView alloc] init];
    if ([cls isEqualToString:@"QTableWidget"] || [cls isEqualToString:@"QTreeWidget"] || [cls isEqualToString:@"QListWidget"]) return Card(node,@[Label([NSString stringWithFormat:@"%@ data view",cls],[UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline],UIColor.secondaryLabelColor)]);

    NSArray *children = BuildChildren(node, preferredPage);
    if ([cls isEqualToString:@"QGroupBox"] || [cls isEqualToString:@"QDockWidget"] || [cls isEqualToString:@"QMenu"] || [cls isEqualToString:@"QMenuBar"]) return Card(node,children);
    UIStackView *stack=VStack();
    NSString *title=S(node[@"title"]);
    if (title.length && ![cls isEqualToString:@"QWidget"] && ![cls isEqualToString:@"QDialog"] && ![cls isEqualToString:@"QMainWindow"]) [stack addArrangedSubview:Label(title,[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline],UIColor.labelColor)];
    for (UIView *child in children) [stack addArrangedSubview:child];
    if (!children.count && !title.length && name.length) [stack addArrangedSubview:Label(name,[UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular],UIColor.tertiaryLabelColor)];
    return stack;
}

@interface RPCS3UpstreamUIBrowserController ()
@property(nonatomic,strong) NSArray<NSDictionary *> *documents;
@end

@implementation RPCS3UpstreamUIBrowserController
- (void)viewDidLoad { [super viewDidLoad]; self.title=@"RPCS3 UI"; self.documents=A(RPCS3LoadBundledQtUIModel()[@"documents"]); }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.documents.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"document"];
    if(!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"document"];
    NSDictionary *document=self.documents[(NSUInteger)indexPath.row], *root=D(document[@"root"]);
    cell.textLabel.text=S(root[@"title"]).length?S(root[@"title"]):S(document[@"class"]);
    cell.detailTextLabel.text=S(document[@"file"]); cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator; return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath { [tableView deselectRowAtIndexPath:indexPath animated:YES]; [self.navigationController pushViewController:[[RPCS3UpstreamUIDocumentController alloc] initWithDocumentFile:S(self.documents[(NSUInteger)indexPath.row][@"file"])] animated:YES]; }
@end

@interface RPCS3UpstreamUIDocumentController ()
@property(nonatomic,copy) NSString *fileName;
@property(nonatomic,copy) NSString *preferredPageName;
@end

@implementation RPCS3UpstreamUIDocumentController
- (instancetype)initWithDocumentFile:(NSString *)fileName { return [self initWithDocumentFile:fileName preferredPageName:nil]; }
- (instancetype)initWithDocumentFile:(NSString *)fileName preferredPageName:(NSString *)pageName { if((self=[super init])){_fileName=[fileName copy];_preferredPageName=[pageName copy]?:@"";}return self; }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor=UIColor.systemBackgroundColor;
    NSDictionary *document=nil;
    for(NSDictionary *candidate in A(RPCS3LoadBundledQtUIModel()[@"documents"])) if([S(candidate[@"file"]) isEqualToString:self.fileName]){document=candidate;break;}
    NSDictionary *root=D(document[@"root"]); self.title=S(root[@"title"]).length?S(root[@"title"]):self.fileName;
    UIScrollView *scroll=[[UIScrollView alloc] init]; scroll.translatesAutoresizingMaskIntoConstraints=NO;
    UIView *content=BuildNode(root,self.preferredPageName); content.translatesAutoresizingMaskIntoConstraints=NO; [scroll addSubview:content]; [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],[scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],[scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],[content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],[content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],[content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],[content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
}
@end
