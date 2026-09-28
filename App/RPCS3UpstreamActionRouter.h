#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RPCS3UpstreamReloadHandler)(void);

/// Routes original RPCS3 QAction identifiers to their UIKit or core-bridge operation.
@interface RPCS3UpstreamActionRouter : NSObject <UIDocumentPickerDelegate>
- (instancetype)initWithOwner:(UIViewController *)owner reloadHandler:(RPCS3UpstreamReloadHandler)reloadHandler;
- (void)handleActionIdentifier:(NSString *)identifier;
@end

NS_ASSUME_NONNULL_END
