#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^RPCS3UpstreamMenuActionHandler)(NSString *actionIdentifier);

/// UIKit conversion of RPCS3 v0.0.40 rpcs3/rpcs3qt/main_window.ui.
/// Titles and identifiers intentionally match upstream QAction/QMenu names.
UIMenu *RPCS3CreateUpstreamMainMenu(RPCS3UpstreamMenuActionHandler handler);

NS_ASSUME_NONNULL_END
