#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface RPCS3BootProgressRecord : NSObject
@property(nonatomic, readonly) BOOL valid;
@property(nonatomic, readonly) uint32_t completed;
@property(nonatomic, readonly) uint32_t total;
@property(nonatomic, readonly) NSString *stage;
@end

@interface RPCS3PerformanceRecord : NSObject
@property(nonatomic, readonly) BOOL fpsValid;
@property(nonatomic, readonly) BOOL cpuValid;
@property(nonatomic, readonly) BOOL gpuValid;
@property(nonatomic, readonly) BOOL memoryValid;
@property(nonatomic, readonly) double framesPerSecond;
@property(nonatomic, readonly) double cpuUsagePercent;
@property(nonatomic, readonly) double gpuUsagePercent;
@property(nonatomic, readonly) uint64_t memoryUsedBytes;
@property(nonatomic, readonly) uint64_t memoryTotalBytes;
@end

@interface RPCS3GameRecord : NSObject
@property(nonatomic, readonly) NSString *titleID;
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) NSString *version;
@property(nonatomic, readonly) NSString *category;
@property(nonatomic, readonly) NSString *iconPath;
@property(nonatomic, readonly) NSString *firmwareVersion;
@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly) BOOL bootable;
@property(nonatomic, readonly) uint64_t sizeOnDisk;
@end

typedef NS_OPTIONS(uint64_t, RPCS3HostPadButton) {
    RPCS3HostPadUp       = UINT64_C(1) << 0,
    RPCS3HostPadDown     = UINT64_C(1) << 1,
    RPCS3HostPadLeft     = UINT64_C(1) << 2,
    RPCS3HostPadRight    = UINT64_C(1) << 3,
    RPCS3HostPadCross    = UINT64_C(1) << 4,
    RPCS3HostPadCircle   = UINT64_C(1) << 5,
    RPCS3HostPadSquare   = UINT64_C(1) << 6,
    RPCS3HostPadTriangle = UINT64_C(1) << 7,
    RPCS3HostPadL1       = UINT64_C(1) << 8,
    RPCS3HostPadR1       = UINT64_C(1) << 9,
    RPCS3HostPadL2       = UINT64_C(1) << 10,
    RPCS3HostPadR2       = UINT64_C(1) << 11,
    RPCS3HostPadL3       = UINT64_C(1) << 12,
    RPCS3HostPadR3       = UINT64_C(1) << 13,
    RPCS3HostPadStart    = UINT64_C(1) << 14,
    RPCS3HostPadSelect   = UINT64_C(1) << 15,
    RPCS3HostPadPS       = UINT64_C(1) << 16,
};

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

- (BOOL)setPlayerIndex:(uint32_t)playerIndex
              connected:(BOOL)connected
                buttons:(uint64_t)buttons
                  leftX:(float)leftX
                  leftY:(float)leftY
                 rightX:(float)rightX
                 rightY:(float)rightY
            leftTrigger:(float)leftTrigger
           rightTrigger:(float)rightTrigger
    NS_SWIFT_NAME(setPlayer(index:connected:buttons:leftX:leftY:rightX:rightY:leftTrigger:rightTrigger:));

- (BOOL)setPlayerOneConnected:(BOOL)connected
                      buttons:(uint64_t)buttons
                        leftX:(float)leftX
                        leftY:(float)leftY
                       rightX:(float)rightX
                       rightY:(float)rightY
                  leftTrigger:(float)leftTrigger
                 rightTrigger:(float)rightTrigger
    NS_SWIFT_NAME(setPlayerOne(connected:buttons:leftX:leftY:rightX:rightY:leftTrigger:rightTrigger:));

- (BOOL)pauseWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)resumeWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)stopWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)shutdownWithError:(NSError * _Nullable * _Nullable)error;


/* SwiftUI convenience surface. Detailed failure text is always available via lastError. */
- (BOOL)startWithSupportPath:(NSString *)supportPath
                  cachePath:(NSString *)cachePath
             jitCapacityMiB:(uint32_t)jitCapacityMiB
    NS_SWIFT_NAME(start(supportPath:cachePath:jitCapacityMiB:));
- (BOOL)attachMetalLayer:(CAMetalLayer *)layer
                   width:(uint32_t)width
                  height:(uint32_t)height
             refreshRate:(float)refreshRate
    NS_SWIFT_NAME(attach(metalLayer:width:height:refreshRate:));
- (BOOL)detachDisplay;
- (BOOL)bootBigPicture;
- (RPCS3BootProgressRecord *)bootProgress;
- (RPCS3PerformanceRecord *)performanceMetrics;
- (NSArray<RPCS3GameRecord *> *)enumerateGames;
- (BOOL)bootGameWithTitleID:(NSString *)titleID NS_SWIFT_NAME(bootGame(titleID:));
- (BOOL)installContentAtPath:(NSString *)path NS_SWIFT_NAME(installContent(atPath:));
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)stop;
- (BOOL)shutdown;

@end

NS_ASSUME_NONNULL_END
