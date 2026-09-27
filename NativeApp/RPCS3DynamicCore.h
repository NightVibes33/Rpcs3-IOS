#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPCS3DynamicCore : NSObject

@property(nonatomic, readonly, getter=isLoaded) BOOL loaded;
@property(nonatomic, readonly, getter=isReady) BOOL ready;
@property(nonatomic, readonly) NSString *buildInfo;
@property(nonatomic, readonly) NSString *lastError;

+ (instancetype)shared;

- (BOOL)loadAndInitializeWithSupportPath:(NSString *)supportPath
                              cachePath:(NSString *)cachePath
                         jitCapacityMiB:(uint32_t)jitCapacityMiB
                                  error:(NSError * _Nullable * _Nullable)error;

- (BOOL)attachMetalLayer:(CAMetalLayer *)layer
                   width:(uint32_t)width
                  height:(uint32_t)height
             refreshRate:(float)refreshRate
                   error:(NSError * _Nullable * _Nullable)error;
- (BOOL)detachDisplayWithError:(NSError * _Nullable * _Nullable)error;

- (BOOL)bootBigPictureWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)installFirmwareAtPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
- (BOOL)installPackageAtPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
- (BOOL)installISOAtPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;
- (BOOL)installZIPAtPath:(NSString *)path error:(NSError * _Nullable * _Nullable)error;

- (BOOL)setPlayerOneConnected:(BOOL)connected
                      buttons:(uint64_t)buttons
                        leftX:(float)leftX
                        leftY:(float)leftY
                       rightX:(float)rightX
                       rightY:(float)rightY
                  leftTrigger:(float)leftTrigger
                 rightTrigger:(float)rightTrigger;

- (BOOL)pauseWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)resumeWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)shutdownWithError:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
