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

@interface RPCS3RPCNConfigRecord : NSObject
@property(nonatomic, readonly) BOOL hasPassword;
@property(nonatomic, readonly) BOOL hasToken;
@property(nonatomic, readonly) BOOL ipv6Support;
@property(nonatomic, readonly) BOOL connected;
@property(nonatomic, readonly) BOOL authenticated;
@property(nonatomic, readonly) NSString *username;
@property(nonatomic, readonly) NSString *host;
@property(nonatomic, readonly) NSString *onlineName;
@property(nonatomic, readonly) NSString *avatarURL;
@end

@interface RPCS3RPCNServerRecord : NSObject
@property(nonatomic, readonly) BOOL selected;
@property(nonatomic, readonly) BOOL removable;
@property(nonatomic, readonly) NSString *serverDescription;
@property(nonatomic, readonly) NSString *host;
@end

@interface RPCS3RuntimePatchRecord : NSObject
@property(nonatomic, readonly) BOOL enabled;
@property(nonatomic, readonly) uint32_t configurableCount;
@property(nonatomic, readonly) NSString *hashValue;
@property(nonatomic, readonly) NSString *title;
@property(nonatomic, readonly) NSString *patchDescription;
@property(nonatomic, readonly) NSString *patchVersion;
@property(nonatomic, readonly) NSString *author;
@property(nonatomic, readonly) NSString *notes;
@property(nonatomic, readonly) NSString *patchGroup;
@property(nonatomic, readonly) NSString *appVersion;
@end

@interface RPCS3SettingOptionRecord : NSObject
@property(nonatomic, readonly) NSString *value;
@property(nonatomic, readonly) NSString *label;
@end

@interface RPCS3SettingRecord : NSObject
@property(nonatomic, readonly) uint32_t kind;
@property(nonatomic, readonly) NSString *key;
@property(nonatomic, readonly) NSString *category;
@property(nonatomic, readonly) NSString *section;
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSString *settingDescription;
@property(nonatomic, readonly) NSString *value;
@property(nonatomic, readonly) NSString *defaultValue;
@property(nonatomic, readonly) double minimum;
@property(nonatomic, readonly) double maximum;
@property(nonatomic, readonly) double step;
@property(nonatomic, readonly) NSString *recommendedValue;
@property(nonatomic, readonly) NSArray<RPCS3SettingOptionRecord *> *options;
@end

@interface RPCS3SettingsSnapshot : NSObject
@property(nonatomic, readonly) NSArray<RPCS3SettingRecord *> *settings;
@property(nonatomic, readonly) BOOL hasCustomConfig;
@end

@interface RPCS3SavestateRecord : NSObject
@property(nonatomic, readonly) BOOL compatible;
@property(nonatomic, readonly) uint64_t size;
@property(nonatomic, readonly) int64_t modifiedTime;
@property(nonatomic, readonly) NSString *identifier;
@end

@interface RPCS3TrophyRecord : NSObject
@property(nonatomic, readonly) uint32_t trophyID;
@property(nonatomic, readonly) uint32_t displayOrder;
@property(nonatomic, readonly) uint32_t grade;
@property(nonatomic, readonly) BOOL earned;
@property(nonatomic, readonly) BOOL hidden;
@property(nonatomic, readonly) uint64_t unlockTimestamp;
@property(nonatomic, readonly) NSString *trophySetID;
@property(nonatomic, readonly) NSString *gameTitle;
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSString *trophyDescription;
@property(nonatomic, readonly) NSString *iconPath;
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
- (BOOL)bootXMB;
- (RPCS3BootProgressRecord *)bootProgress;
- (RPCS3PerformanceRecord *)performanceMetrics;
- (NSArray<RPCS3RuntimePatchRecord *> *)runtimePatchesForTitleID:(NSString *)titleID
                                                    appVersion:(NSString *)appVersion
    NS_SWIFT_NAME(runtimePatches(titleID:appVersion:));
- (BOOL)setRuntimePatchForTitleID:(NSString *)titleID
                             hash:(NSString *)hashValue
                            title:(NSString *)title
                       appVersion:(NSString *)appVersion
                      description:(NSString *)description
                          enabled:(BOOL)enabled
    NS_SWIFT_NAME(setRuntimePatch(titleID:hash:title:appVersion:description:enabled:));

- (RPCS3RPCNConfigRecord *)rpcnConfig;
- (NSArray<RPCS3RPCNServerRecord *> *)rpcnServers;
- (BOOL)setRPCNServerHost:(NSString *)host NS_SWIFT_NAME(setRPCNServer(host:));
- (BOOL)addRPCNServerDescription:(NSString *)description
                            host:(NSString *)host
    NS_SWIFT_NAME(addRPCNServer(description:host:));
- (BOOL)removeRPCNServerDescription:(NSString *)description
                               host:(NSString *)host
    NS_SWIFT_NAME(removeRPCNServer(description:host:));
- (BOOL)setRPCNCredentialsUsername:(NSString *)username
                          password:(NSString *)password
                             token:(NSString *)token
                              ipv6:(BOOL)ipv6
    NS_SWIFT_NAME(setRPCNCredentials(username:password:token:ipv6:));
- (BOOL)testRPCNAccount;

- (BOOL)updateConfigDatabaseData:(NSData *)data NS_SWIFT_NAME(updateConfigDatabase(data:));

- (RPCS3SettingsSnapshot *)globalSettings;
- (RPCS3SettingsSnapshot *)gameSettingsForTitleID:(NSString *)titleID
    NS_SWIFT_NAME(gameSettings(titleID:));
- (BOOL)setGlobalSettingKey:(NSString *)key value:(NSString *)value
    NS_SWIFT_NAME(setGlobalSetting(key:value:));
- (BOOL)resetGlobalSettings;
- (BOOL)setGameSettingForTitleID:(NSString *)titleID
                             key:(NSString *)key
                           value:(NSString *)value
    NS_SWIFT_NAME(setGameSetting(titleID:key:value:));
- (BOOL)resetGameSettingsForTitleID:(NSString *)titleID
    NS_SWIFT_NAME(resetGameSettings(titleID:));
- (BOOL)removeGameSettingsForTitleID:(NSString *)titleID
    NS_SWIFT_NAME(removeGameSettings(titleID:));
- (NSArray<RPCS3GameRecord *> *)enumerateGames;
- (NSArray<RPCS3SavestateRecord *> *)enumerateSavestatesForTitleID:(NSString *)titleID
    NS_SWIFT_NAME(enumerateSavestates(titleID:));
- (NSArray<RPCS3TrophyRecord *> *)enumerateTrophiesForTitleID:(NSString *)titleID
    NS_SWIFT_NAME(enumerateTrophies(titleID:));
- (BOOL)bootGameWithTitleID:(NSString *)titleID NS_SWIFT_NAME(bootGame(titleID:));
- (BOOL)bootGameWithTitleID:(NSString *)titleID
                savestateID:(NSString *)savestateID
    NS_SWIFT_NAME(bootGame(titleID:savestateID:));
- (BOOL)installContentAtPath:(NSString *)path NS_SWIFT_NAME(installContent(atPath:));
- (BOOL)pause;
- (BOOL)resume;
- (BOOL)stop;
- (BOOL)shutdown;

@end

NS_ASSUME_NONNULL_END
