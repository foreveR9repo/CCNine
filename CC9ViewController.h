#import <UIKit/UIKit.h>

// YES sur les iPhone sans bouton Home (Face ID / encoche) : le geste natif part alors du coin haut-droit
BOOL CC9DeviceHasNoHomeButton(void);

@interface CC9Controller : NSObject
+ (instancetype)shared;
@property (nonatomic, readonly) BOOL isOpen;
// Pilotés par les hooks du geste natif (le paramètre est le recognizer natif, utilisé en lecture seule)
- (void)gestureBegan:(id)gr;
- (void)gestureChanged:(id)gr;
- (void)gestureEnded:(id)gr;
- (void)gestureCancelled:(id)gr;
- (void)prewarm;
- (void)installEdgeTrigger;   // zone de geste en bas à gauche (appareils sans bouton Home)
- (void)presentAnimated:(BOOL)animated;
- (void)dismissAnimated:(BOOL)animated;
@end
