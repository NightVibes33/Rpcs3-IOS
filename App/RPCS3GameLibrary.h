#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPCS3GameEntry : NSObject
@property(nonatomic,copy) NSString *title;
@property(nonatomic,copy) NSString *titleID;
@property(nonatomic,copy) NSString *category;
@property(nonatomic,copy) NSString *version;
@property(nonatomic,strong) NSURL *rootURL;
@property(nonatomic,strong,nullable) NSURL *bootURL;
@property(nonatomic,strong,nullable) NSURL *iconURL;
@end

@interface RPCS3GameLibrary : NSObject
+ (NSArray<RPCS3GameEntry *> *)scanRoot:(NSString *)rootPath;
@end

NS_ASSUME_NONNULL_END
