#import <UIKit/UIKit.h>
extern NSString *const CC9StateChanged;
void CC9Log(NSString *m);   // journal : /var/mobile/Documents/CCNine_log.txt

typedef NS_ENUM(NSInteger, CC9Toggle) {
    CC9ToggleAirplane = 1, CC9ToggleWiFi, CC9ToggleBluetooth, CC9ToggleDND,
    CC9ToggleRotation, CC9ToggleFlashlight, CC9ToggleNightShift
};

@interface CC9Backend : NSObject
+ (instancetype)shared;
- (BOOL)stateFor:(CC9Toggle)t;
- (void)toggle:(CC9Toggle)t;
- (float)brightness;
- (void)setBrightness:(float)v;
- (float)volume;
- (void)setVolume:(float)v;
- (void)sendMediaCommand:(int)cmd; // 2 = play/pause, 4 = next, 5 = prev
- (void)fetchNowPlaying:(void (^)(NSString *title, NSString *artist, BOOL playing))cb;
- (void)launchBundleID:(NSString *)bid;
@end
