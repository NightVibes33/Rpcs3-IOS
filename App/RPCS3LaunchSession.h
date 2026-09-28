#import <UIKit/UIKit.h>
@class RPCS3GameEntry;
NS_ASSUME_NONNULL_BEGIN
@interface RPCS3LaunchSessionController : UIViewController
- (instancetype)initWithEntry:(RPCS3GameEntry *)entry;
@end
NS_ASSUME_NONNULL_END
