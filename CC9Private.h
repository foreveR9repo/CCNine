// Déclarations des classes privées. Aucune n'est liée : tout passe par objc_getClass().
#import <UIKit/UIKit.h>

@interface RadiosPreferences : NSObject
- (BOOL)airplaneMode; - (void)setAirplaneMode:(BOOL)m; - (void)synchronize;
@end
@interface SBWiFiManager : NSObject
+ (instancetype)sharedInstance; - (BOOL)wiFiEnabled; - (void)setWiFiEnabled:(BOOL)e;
@end
@interface BluetoothManager : NSObject
+ (instancetype)sharedInstance; - (BOOL)powered; - (void)setPowered:(BOOL)p; - (void)setEnabled:(BOOL)e;
@end
@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance; - (BOOL)isUserLocked; - (void)lock; - (void)unlock;
@end
@interface CBBlueLightClient : NSObject
- (BOOL)setEnabled:(BOOL)e; - (BOOL)getBlueLightStatus:(void *)status;
@end
@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace; - (BOOL)openApplicationWithBundleID:(NSString *)b;
@end
@interface AVSystemController : NSObject
+ (instancetype)sharedAVSystemController;
- (BOOL)getVolume:(float *)v forCategory:(NSString *)c;
- (BOOL)setVolumeTo:(float)v forCategory:(NSString *)c;
@end
// Focus / Ne pas déranger (iOS 15+) – À VÉRIFIER sur ta version exacte
@interface DNDState : NSObject - (BOOL)isActive; @end
@interface DNDStateService : NSObject
+ (id)serviceForClientIdentifier:(NSString *)i; - (id)queryCurrentStateWithError:(NSError **)e;
@end
@interface DNDModeAssertionDetails : NSObject
+ (id)userRequestedAssertionDetailsWithIdentifier:(NSString *)i modeIdentifier:(NSString *)m lifetime:(id)l;
@end
@interface DNDModeAssertionService : NSObject
+ (id)serviceForClientIdentifier:(NSString *)i;
- (id)takeModeAssertionWithDetails:(id)d error:(NSError **)e;
- (BOOL)invalidateAllActiveModeAssertionsWithError:(NSError **)e;
@end
