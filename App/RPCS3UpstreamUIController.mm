#import "RPCS3UpstreamUIController.h"

static NSString *RPCS3String(id value) {
    return [value isKindOfClass:NSString.class] ? value : @"";
}

static NSArray *RPCS3Array(id value) {
    return [value isKindOfClass:NSArray.class] ? value : @[];
}

static NSDictionary *RPCS3Dictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

NSDictionary *RPCS3LoadBundledQtUIModel(void) {
    static NSDictionary *model;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [NSBundle.mainBundle pathForResource:@"RPCS3QtUIModel" ofType:@"json"];
        if (!path.length) return;
        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data.length) return;
        id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([value isKindOfClass:NSDictionary.class]) model = value;
    });
    return model;
}

static UILabel *RPCS3Label(NSString *text, UIFont *font, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    label.numberOfLines = 0;
    label.adjustsFontForContentSizeCategory = YES;
    return label;
}

static UIStackView *RPCS3VerticalStack(void) {
    UIStackView *stack = [[UIStackView alloc] init];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 10;
    stack.alignment = UIStackViewAlignmentFill;
    return stack;
}

static UIView *RPCS3BuildNode(NSDictionary *node, NSString *preferredPageName);

@interface RPCS3QtPageHostView : UIView
@property(nonatomic,strong) NSArray<NSDictionary *> *pages;
@property(nonatomic,strong) UISegmentedControl *segments;
@property(nonatomic,strong) UIView *content;
@property(nonatomic,copy) NSString *preferredPageName;
@end

@implementation RPCS3QtPageHostView
- (instancetype)initWithNode:(NSDictionary *)node preferredPageName:(NSString *)preferredPageName {
    if ((self = [super init])) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.pages = RPCS3Array(node[@"children"]);
        self.preferredPageName = preferredPageName ?: @"";
        NSMutableArray<NSString *> *titles = [NSMutableArray array];
        NSInteger selected = 0;
        [self.pages enumerateObjectsUsingBlock:^(NSDictionary *page, NSUInteger index, BOOL *stop) {
            (void)stop;
            NSString *title = RPCS3String(page[@"title"]);
            if (!title.length) title = RPCS3String(page[@"name"]);
            [titles addObject:title.length ? title : [NSString stringWithFormat:@"Page %lu", (unsigned long)index + 1]];
            if (self.preferredPageName.length && [RPCS3String(page[@"name"]) isEqualToString:self.preferredPageName]) selected = (NSInteger)index;
        }];

        self.segments = [[UISegmentedControl alloc] initWithItems:titles];
        self.segments.translatesAutoresizingMaskIntoConstraints = NO;
        self.segments.apportionsSegmentWidthsByContent = YES;
        self.segments.selectedSegmentIndex = titles.count ? selected : UISegmentedControlNoSegment;
        [self.segments addTarget:self action:@selector(changePage:) forControlEvents:UIControlEventValueChanged];

        UIScrollView *tabScroll = [[UIScrollView alloc] init];
        tabScroll.translatesAutoresizingMaskIntoConstraints = NO;
        tabScroll.showsHorizontalScrollIndicator = NO;
        [tabScroll addSubview:self.segments];

        self.content = [[UIView alloc] init];
        self.content.translatesAutoresizingMaskIntoConstraints = NO;

        UIStackView *stack = RPCS3VerticalStack();
        [stack addArrangedSubview:tabScroll];
        [stack addArrangedSubview:self.content];
        [self addSubview:stack];
        [NSLayoutConstraint activateConstraints:@[
            [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
            [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
            [tabScroll.heightAnchor constraintEqualToConstant:38],
            [self.segments.topAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.topAnchor],
            [self.segments.leadingAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.leadingAnchor],
            [self.segments.trailingAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.trailingAnchor],
            [self.segments.bottomAnchor constraintEqualToAnchor:tabScroll.contentLayoutGuide.bottomAnchor],
            [self.segments.heightAnchor constraintEqualToAnchor:tabScroll.frameLayoutGuide.heightAnchor],
            [self.content.heightAnchor constraintGreaterThanOrEqualToConstant:80]
        ]];
        [self showPage:selected];
    }
    return self;
}

- (void)changePage:(UISegmentedControl *)sender { [self showPage:sender.selectedSegmentIndex]; }

- (void)showPage:(NSInteger)index {
    for (UIView *view in self.content.subviews) [view removeFromSuperview];
    if (index < 0 || index >= (NSInteger)self.pages.count) return;
    NSDictionary *page = self.pages[(NSUInteger)index];
    UIView *pageView = RPCS3BuildNode(page, self.preferredPageName);
    pageView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.content addSubview:pageView];
    [NSLayoutConstraint activateConstraints:@[
        [pageView.topAnchor constraintEqualToAnchor:self.content.topAnchor],
        [pageView.leadingAnchor constraintEqualToAnchor:self.content.leadingAnchor],
        [pageView.trailingAnchor constraintEqualToAnchor:self.content.trailingAnchor],
        [pageView.bottomAnchor constraintEqualToAnchor:self.content.bottomAnchor]
    ]];
}
@end

static UIView *RPCS3NamedRow(NSDictionary *node, UIView *control) {
    NSString *title = RPCS3String(node[@"text"]);
    if (!title.length) title = RPCS3String(node[@"title"]);
    NSString *name = RPCS3String(node[@"name"]);
    if (!title.length) title = name;

    UIStackView *labels = RPCS3VerticalStack();
    labels.spacing = 2;
    [labels addArrangedSubview:RPCS3Label(title.length ? title : @"RPCS3 option", [UIFont preferredFontForTextStyle:UIFontTextStyleBody], UIColor.labelColor)];
    if (name.length && ![name isEqualToString:title]) {
        [labels addArrangedSubview:RPCS3Label(name, [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular], UIColor.tertiaryLabelColor)];
    }

    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:control ? @[labels, control] : @[labels]];
    row.translatesAutoresizingMaskIntoConstraints = NO;
    row.axis = UILayoutConstraintAxisHorizontal;
    row.alignment = UIStackViewAlignmentCenter;
    row.spacing = 12;
    labels.setContentHuggingPriority = UILayoutPriorityDefaultLow;
    if (control) [control setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    return row;
}

static UIView *RPCS3Card(NSDictionary *node, NSArray<UIView *> *children) {
    UIView *card = [[UIView alloc] init];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = UIColor.secondarySystemBackgroundColor;
    card.layer.cornerRadius = 12;

    UIStackView *stack = RPCS3VerticalStack();
    stack.spacing = 9;
    NSString *title = RPCS3String(node[@"title"]);
    if (title.length) [stack addArrangedSubview:RPCS3Label(title, [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline], UIColor.labelColor)];
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

static NSArray<UIView *> *RPCS3BuildChildren(NSDictionary *node, NSString *preferredPageName) {
    NSMutableArray<UIView *> *views = [NSMutableArray array];
    for (NSDictionary *child in RPCS3Array(node[@"children"])) {
        [views addObject:RPCS3BuildNode(child, preferredPageName)];
    }
    return views;
}

static UIView *RPCS3BuildNode(NSDictionary *node, NSString *preferredPageName) {
    NSString *cls = RPCS3String(node[@"class"]);
    NSString *text = RPCS3String(node[@"text"]);
    NSArray *children = RPCS3Array(node[@"children"]);

    if ([cls isEqualToString:@"QTabWidget"] || [cls isEqualToString:@"QToolBox"] || [cls isEqualToString:@"QStackedWidget"]) {
        return [[RPCS3QtPageHostView alloc] initWithNode:node preferredPageName:preferredPageName];
    }

    if ([cls isEqualToString:@"QCheckBox"]) {
        UISwitch *toggle = [[UISwitch alloc] init];
        toggle.on = [RPCS3String(node[@"checked"]) isEqualToString:@"true"];
        toggle.accessibilityIdentifier = RPCS3String(node[@"name"]);
        return RPCS3NamedRow(node, toggle);
    }

    if ([cls isEqualToString:@"QRadioButton"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setImage:[UIImage systemImageNamed:@"circle"] forState:UIControlStateNormal];
        button.accessibilityIdentifier = RPCS3String(node[@"name"]);
        return RPCS3NamedRow(node, button);
    }

    if ([cls isEqualToString:@"QComboBox"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:@"Choose" forState:UIControlStateNormal];
        NSArray *items = RPCS3Array(node[@"items"]);
        if (items.count) {
            NSMutableArray<UIMenuElement *> *actions = [NSMutableArray array];
            for (NSString *item in items) [actions addObject:[UIAction actionWithTitle:item handler:^(__kindof UIAction *action) { [button setTitle:action.title forState:UIControlStateNormal]; }]];
            button.menu = [UIMenu menuWithChildren:actions];
            button.showsMenuAsPrimaryAction = YES;
        }
        return RPCS3NamedRow(node, button);
    }

    if ([cls isEqualToString:@"QSlider"]) {
        UISlider *slider = [[UISlider alloc] init];
        slider.translatesAutoresizingMaskIntoConstraints = NO;
        slider.minimumValue = RPCS3String(node[@"minimum"]).length ? [RPCS3String(node[@"minimum"]) floatValue] : 0;
        slider.maximumValue = RPCS3String(node[@"maximum"]).length ? [RPCS3String(node[@"maximum"]) floatValue] : 100;
        slider.value = RPCS3String(node[@"value"]).length ? [RPCS3String(node[@"value"]) floatValue] : slider.minimumValue;
        [slider.widthAnchor constraintGreaterThanOrEqualToConstant:120].active = YES;
        return RPCS3NamedRow(node, slider);
    }

    if ([cls isEqualToString:@"QSpinBox"] || [cls isEqualToString:@"QDoubleSpinBox"]) {
        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.minimumValue = RPCS3String(node[@"minimum"]).length ? [RPCS3String(node[@"minimum"]) doubleValue] : 0;
        stepper.maximumValue = RPCS3String(node[@"maximum"]).length ? [RPCS3String(node[@"maximum"]) doubleValue] : 100;
        stepper.value = RPCS3String(node[@"value"]).length ? [RPCS3String(node[@"value"]) doubleValue] : stepper.minimumValue;
        return RPCS3NamedRow(node, stepper);
    }

    if ([cls isEqualToString:@"QPushButton"] || [cls isEqualToString:@"QToolButton"]) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:text.length ? text : RPCS3String(node[@"name"]) forState:UIControlStateNormal];
        button.configuration = [UIButtonConfiguration borderedButtonConfiguration];
        button.accessibilityIdentifier = RPCS3String(node[@"name"]);
        return button;
    }

    if ([cls isEqualToString:@"QLineEdit"]) {
        UITextField *field = [[UITextField alloc] init];
        field.borderStyle = UITextBorderStyleRoundedRect;
        field.placeholder = RPCS3String(node[@"placeholder"]);
        field.accessibilityIdentifier = RPCS3String(node[@"name"]);
        return RPCS3NamedRow(node, field);
    }

    if ([cls isEqualToString:@"QLabel"]) {
        if (!text.length) return [[UIView alloc] init];
        return RPCS3Label(text, [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote], UIColor.secondaryLabelColor);
    }

    if ([cls isEqualToString:@"QTableWidget"] || [cls isEqualToString:@"QTreeWidget"] || [cls isEqualToString:@"QListWidget"]) {
        UILabel *placeholder = RPCS3Label([NSString stringWithFormat:@"%@ data view", cls], [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline], UIColor.secondaryLabelColor);
        return RPCS3Card(node, @[placeholder]);
    }

    NSArray<UIView *> *builtChildren = RPCS3BuildChildren(node, preferredPageName);
    if ([cls isEqualToString:@"QGroupBox"] || [cls isEqualToString:@"QDockWidget"] || [cls isEqualToString:@"QMenu"] || [cls isEqualToString:@"QMenuBar"]) {
        return RPCS3Card(node, builtChildren);
    }

    UIStackView *stack = RPCS3VerticalStack();
    NSString *title = RPCS3String(node[@"title"]);
    if (title.length && ![cls isEqualToString:@"QWidget"] && ![cls isEqualToString:@"QDialog"] && ![cls isEqualToString:@"QMainWindow"]) {
        [stack addArrangedSubview:RPCS3Label(title, [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline], UIColor.labelColor)];
    }
    for (UIView *child in builtChildren) [stack addArrangedSubview:child];
    if (!builtChildren.count && !title.length) {
        NSString *name = RPCS3String(node[@"name"]);
        if (name.length) [stack addArrangedSubview:RPCS3Label(name, [UIFont monospacedSystemFontOfSize:10 weight:UIFontWeightRegular], UIColor.tertiaryLabelColor)];
    }
    return stack;
}

@interface RPCS3UpstreamUIBrowserController ()
@property(nonatomic,strong) NSArray<NSDictionary *> *documents;
@end

@implementation RPCS3UpstreamUIBrowserController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"RPCS3 UI";
    self.documents = RPCS3Array(RPCS3LoadBundledQtUIModel()[@"documents"]);
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"document"];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return self.documents.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"document" forIndexPath:indexPath];
    NSDictionary *document = self.documents[(NSUInteger)indexPath.row];
    NSDictionary *root = RPCS3Dictionary(document[@"root"]);
    cell.textLabel.text = RPCS3String(root[@"title"]).length ? RPCS3String(root[@"title"]) : RPCS3String(document[@"class"]);
    cell.detailTextLabel.text = RPCS3String(document[@"file"]);
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *file = RPCS3String(self.documents[(NSUInteger)indexPath.row][@"file"]);
    [self.navigationController pushViewController:[[RPCS3UpstreamUIDocumentController alloc] initWithDocumentFile:file] animated:YES];
}
@end

@interface RPCS3UpstreamUIDocumentController ()
@property(nonatomic,copy) NSString *fileName;
@property(nonatomic,copy) NSString *preferredPageName;
@end

@implementation RPCS3UpstreamUIDocumentController
- (instancetype)initWithDocumentFile:(NSString *)fileName { return [self initWithDocumentFile:fileName preferredPageName:nil]; }
- (instancetype)initWithDocumentFile:(NSString *)fileName preferredPageName:(NSString *)pageName {
    if ((self = [super init])) { _fileName = [fileName copy]; _preferredPageName = [pageName copy] ?: @""; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    NSDictionary *document;
    for (NSDictionary *candidate in RPCS3Array(RPCS3LoadBundledQtUIModel()[@"documents"])) {
        if ([RPCS3String(candidate[@"file"]) isEqualToString:self.fileName]) { document = candidate; break; }
    }
    NSDictionary *root = RPCS3Dictionary(document[@"root"]);
    self.title = RPCS3String(root[@"title"]).length ? RPCS3String(root[@"title"]) : self.fileName;

    UIScrollView *scroll = [[UIScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    UIView *content = RPCS3BuildNode(root, self.preferredPageName);
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:content];
    [self.view addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[
        [scroll.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [content.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor constant:16],
        [content.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor constant:16],
        [content.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor constant:-16],
        [content.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor constant:-16],
        [content.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor constant:-32]
    ]];
}
@end
