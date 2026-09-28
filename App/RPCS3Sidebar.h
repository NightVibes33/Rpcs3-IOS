#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPCS3SidebarController : UITableViewController
- (instancetype)initWithSplitViewController:(UISplitViewController *)split
                                     titles:(NSArray<NSString *> *)titles
                                      icons:(NSArray<NSString *> *)icons
                               destinations:(NSArray<UIViewController *> *)destinations;
@end

NS_ASSUME_NONNULL_END
