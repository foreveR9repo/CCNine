#import <UIKit/UIKit.h>

@interface CC9Controller : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL isOpen;
// Pilotés par les hooks du geste natif (le paramètre est le recognizer natif, utilisé en lecture seule)
- (void)gestureBegan:(id)gr;
- (void)gestureChanged:(id)gr;
- (void)gestureEnded:(id)gr;
- (void)gestureCancelled:(id)gr;
- (void)presentAnimated:(BOOL)animated;
- (void)dismissAnimated:(BOOL)animated;
@end
