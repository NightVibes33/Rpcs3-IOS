#import "RPCS3Sidebar.h"

@interface RPCS3SidebarController ()
@property(nonatomic,weak) UISplitViewController *splitController;
@property(nonatomic,strong) NSArray<NSString *> *titles;
@property(nonatomic,strong) NSArray<NSString *> *icons;
@property(nonatomic,strong) NSArray<UIViewController *> *destinations;
@end

@implementation RPCS3SidebarController
- (instancetype)initWithSplitViewController:(UISplitViewController *)split
                                     titles:(NSArray<NSString *> *)titles
                                      icons:(NSArray<NSString *> *)icons
                               destinations:(NSArray<UIViewController *> *)destinations {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _splitController = split;
        _titles = [titles copy];
        _icons = [icons copy];
        _destinations = [destinations copy];
        self.title = @"RPCS3";
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.clearsSelectionOnViewWillAppear = NO;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"sidebar"];
    if (self.titles.count) {
        NSIndexPath *first = [NSIndexPath indexPathForRow:0 inSection:0];
        [self.tableView selectRowAtIndexPath:first animated:NO scrollPosition:UITableViewScrollPositionNone];
    }
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return MIN(self.titles.count, self.destinations.count);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"sidebar" forIndexPath:indexPath];
    UIListContentConfiguration *content = [UIListContentConfiguration sidebarCellConfiguration];
    content.text = self.titles[indexPath.row];
    if (indexPath.row < self.icons.count) content.image = [UIImage systemImageNamed:self.icons[indexPath.row]];
    cell.contentConfiguration = content;
    cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (indexPath.row >= self.destinations.count) return;
    [self.splitController setViewController:self.destinations[indexPath.row] forColumn:UISplitViewControllerColumnSecondary];
    [self.splitController showColumn:UISplitViewControllerColumnSecondary];
}
@end
