#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "CC9ViewController.h"

// ---------- Garde-fous anti respring-loop ----------
// 1) kill-switch : crée ce fichier (SSH / Filza) pour désactiver le tweak sans recompiler
// 2) compteur : >=4 chargements en <60 s => le tweak se désactive tout seul
#define CC9_DIR   @"/var/mobile/Library/Preferences"
#define CC9_KILL  CC9_DIR @"/com.example.ccnine.disable"
#define CC9_GUARD CC9_DIR @"/com.example.ccnine.guard.plist"

static BOOL CC9GuardAllows(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:CC9_KILL]) return NO;
    NSDictionary *g = [NSDictionary dictionaryWithContentsOfFile:CC9_GUARD];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970, ts = [g[@"ts"] doubleValue];
    NSInteger n = (g && now - ts < 60) ? [g[@"n"] integerValue] + 1 : 1;
    [@{ @"n": @(n), @"ts": @(g && now - ts < 60 ? ts : now) } writeToFile:CC9_GUARD atomically:YES];
    if (n >= 4) { [@"" writeToFile:CC9_KILL atomically:YES encoding:NSUTF8StringEncoding error:nil]; return NO; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
        [NSFileManager.defaultManager removeItemAtPath:CC9_GUARD error:nil];   // démarrage stable => reset
    });
    return YES;
}

// ---------- Désactivation du Control Center natif + redirection ----------
// Noms basés sur iOS 15-17 : À VÉRIFIER avec `class-dump`/FLEX sur ta version exacte.
%group CCHooks

%hook SBControlCenterController
- (void)_showControlCenterGestureBeganWithGestureRecognizer:(id)gr     { [[CC9Controller shared] gestureBegan:gr]; }
- (void)_showControlCenterGestureChangedWithGestureRecognizer:(id)gr   { [[CC9Controller shared] gestureChanged:gr]; }
- (void)_showControlCenterGestureEndedWithGestureRecognizer:(id)gr     { [[CC9Controller shared] gestureEnded:gr]; }
- (void)_showControlCenterGestureCancelledWithGestureRecognizer:(id)gr { [[CC9Controller shared] gestureCancelled:gr]; }
- (void)presentAnimated:(BOOL)a                                        { [[CC9Controller shared] presentAnimated:a]; }
- (void)presentAnimated:(BOOL)a completion:(void (^)(void))c           { [[CC9Controller shared] presentAnimated:a]; if (c) c(); }  // ne jamais perdre un completion
- (void)dismissAnimated:(BOOL)a                                        { [[CC9Controller shared] dismissAnimated:a]; }
- (void)dismissAnimated:(BOOL)a completion:(void (^)(void))c           { [[CC9Controller shared] dismissAnimated:a]; if (c) c(); }
- (BOOL)isPresented { return NO; }   // le natif se croit toujours fermé
- (BOOL)isVisible   { return NO; }
%end

%end

// Bouton Home : ferme notre CC (sinon il reste affiché au-dessus de tout)
%group HomeHooks
%hook SBHomeHardwareButtonActions
- (void)performSinglePressUpActions {
    if ([CC9Controller shared].isOpen) { [[CC9Controller shared] dismissAnimated:YES]; return; }
    %orig;
}
%end
%end

%ctor {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"]) return;
        if (@available(iOS 16.0, *)) {} else return;
        if (!CC9GuardAllows()) { NSLog(@"[CCNine] désactivé (kill-switch / crash-loop guard)"); return; }
        if (!objc_getClass("SBControlCenterController")) { NSLog(@"[CCNine] SBControlCenterController introuvable"); return; }
        %init(CCHooks);
        if (objc_getClass("SBHomeHardwareButtonActions")) %init(HomeHooks);
        NSLog(@"[CCNine] chargé");
    }
}
