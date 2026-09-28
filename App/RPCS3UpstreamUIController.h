#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Browser and renderer for the JSON model exported directly from RPCS3's
/// pinned rpcs3qt/*.ui files. The renderer preserves nested tab widgets,
/// stacked pages, toolboxes, docks, group boxes, controls, and object names.
@interface RPCS3UpstreamUIBrowserController : UITableViewController
@end

@interface RPCS3UpstreamUIDocumentController : UIViewController
- (instancetype)initWithDocumentFile:(NSString *)fileName;
- (instancetype)initWithDocumentFile:(NSString *)fileName preferredPageName:(nullable NSString *)pageName;
@end

NSDictionary * _Nullable RPCS3LoadBundledQtUIModel(void);

NS_ASSUME_NONNULL_END
