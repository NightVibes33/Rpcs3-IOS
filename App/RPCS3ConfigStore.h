#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *RPCS3IOSConfigPath(void);
FOUNDATION_EXPORT BOOL RPCS3IOSWriteConfig(NSDictionary *values, NSError **error);
FOUNDATION_EXPORT NSString *RPCS3IOSReadConfig(void);
FOUNDATION_EXPORT NSString *RPCS3IOSReadLatestLog(void);

NS_ASSUME_NONNULL_END
