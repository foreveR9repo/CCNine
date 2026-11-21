#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import "CC9ViewController.h"

// ---------- Garde-fous anti respring-loop ----------
// 1) kill-switch : crée ce fichier (Filza) pour désactiver le tweak sans recompiler
// 2) compteur : >=4 chargements en <60 s => le tweak se désactive tout seul
#define CC9_DIR   @"/var/mobile/Library/Preferences"
#define CC9_KILL  CC9_DIR @"/com.example.ccnine.disable"
#define CC9_GUARD CC9_DIR @"/com.example.ccnine.guard.plist"
#define CC9_DUMP  @"/var/mobile/Documents/CCNine_dump.txt"

static BOOL CC9GuardAllows(void) {
    NSFileManager *fm = NSFileManager.defaultManager;
    if ([fm fileExistsAtPath:CC9_KILL]) return NO;
    NSDictionary *g = [NSDictionary dictionaryWithContentsOfFile:CC9_GUARD];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970, ts = [g[@"ts"] doubleValue];
    NSInteger n = (g && now - ts < 60) ? [g[@"n"] integerValue] + 1 : 1;
    [@{ @"n": @(n), @"ts": @(g && now - ts < 60 ? ts : now) } writeToFile:CC9_GUARD atomically:YES];
    if (n >= 4) { [@"" writeToFile:CC9_KILL atomically:YES encoding:NSUTF8StringEncoding error:nil]; return NO; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{
        [NSFileManager.defaultManager removeItemAtPath:CC9_GUARD error:nil];
    });
    return YES;
}

// ---------- Outils ----------
static NSMutableArray<NSString *> *gHooked;   // méthodes interceptées dynamiquement (pour le diagnostic)

static id CC9NativeCC(void) {
    Class c = objc_getClass("SBControlCenterController");
    if (!c) return nil;
    SEL a = @selector(sharedInstanceIfExists), b = @selector(sharedInstance);
    if ([c respondsToSelector:a]) return ((id (*)(Class, SEL))objc_msgSend)(c, a);
    if ([c respondsToSelector:b]) return ((id (*)(Class, SEL))objc_msgSend)(c, b);
    return nil;
}

// Referme le CC natif sans animation (il ne doit JAMAIS rester affiché à côté du nôtre)
static void CC9DismissNative(void) {
    id inst = CC9NativeCC(); if (!inst) return;
    @try {
        SEL a = @selector(dismissAnimated:), b = @selector(dismissAnimated:completion:);
        if ([inst respondsToSelector:a]) ((void (*)(id, SEL, BOOL))objc_msgSend)(inst, a, NO);
        else if ([inst respondsToSelector:b]) ((void (*)(id, SEL, BOOL, id))objc_msgSend)(inst, b, NO, nil);
    } @catch (NSException *e) { NSLog(@"[CCNine] dismiss native: %@", e); }
}

static void CC9Route(int kind, id gr) {
    CC9Controller *c = [CC9Controller shared];
    switch (kind) {
        case 0: [c gestureBegan:gr]; break;
        case 1: [c gestureChanged:gr]; break;
        case 2: [c gestureEnded:gr]; break;
        default: [c gestureCancelled:gr]; break;
    }
}
static void CC9RouteByState(id gr) {
    if (![gr respondsToSelector:@selector(state)]) return;
    switch ([(UIGestureRecognizer *)gr state]) {
        case UIGestureRecognizerStateBegan: CC9Route(0, gr); break;
        case UIGestureRecognizerStateChanged: CC9Route(1, gr); break;
        case UIGestureRecognizerStateEnded: CC9Route(2, gr); break;
        case UIGestureRecognizerStateCancelled: case UIGestureRecognizerStateFailed: CC9Route(3, gr); break;
        default: break;
    }
}

// ---------- Interception DYNAMIQUE du geste natif ----------
// Les noms de méthodes changent selon iOS : on scanne SBControlCenterController et on remplace
// toute méthode "void m:(id)" dont le nom contient "gesture" (+ began/changed/ended/cancel, ou show/present/reveal).
static void CC9HookGestureMethods(void) {
    Class c = objc_getClass("SBControlCenterController"); if (!c) return;
    unsigned n = 0; Method *ms = class_copyMethodList(c, &n);
    for (unsigned i = 0; i < n; i++) {
        SEL s = method_getName(ms[i]); const char *enc = method_getTypeEncoding(ms[i]);
        if (!enc || strcmp(enc, "v24@0:8@16") != 0) continue;
        NSString *l = NSStringFromSelector(s).lowercaseString;
        if (![l containsString:@"gesture"]) continue;
        if ([l containsString:@"dismiss"] || [l containsString:@"hide"] || [l containsString:@"close"]) continue;
        IMP imp = NULL;
        if ([l containsString:@"began"])        imp = imp_implementationWithBlock(^(id _s, id gr) { CC9Route(0, gr); });
        else if ([l containsString:@"changed"]) imp = imp_implementationWithBlock(^(id _s, id gr) { CC9Route(1, gr); });
        else if ([l containsString:@"ended"])   imp = imp_implementationWithBlock(^(id _s, id gr) { CC9Route(2, gr); });
        else if ([l containsString:@"cancel"] || [l containsString:@"fail"])
                                                imp = imp_implementationWithBlock(^(id _s, id gr) { CC9Route(3, gr); });
        else if ([l containsString:@"show"] || [l containsString:@"present"] || [l containsString:@"reveal"] || [l containsString:@"pan"])
                                                imp = imp_implementationWithBlock(^(id _s, id gr) { CC9RouteByState(gr); });
        if (!imp) continue;
        class_replaceMethod(c, s, imp, enc);
        [gHooked addObject:NSStringFromSelector(s)];
    }
    free(ms);
}

// ---------- Diagnostic : fichier lisible avec Filza ----------
static void CC9DumpClass(const char *name, NSMutableString *o) {
    Class c = objc_getClass(name);
    if (!c) { [o appendFormat:@"\n=== %s : ABSENTE ===\n", name]; return; }
    Class sup = class_getSuperclass(c);
    [o appendFormat:@"\n=== %s (super: %s) ===\n", name, sup ? class_getName(sup) : "-"];
    for (int meta = 0; meta < 2; meta++) {
        unsigned n = 0; Method *ms = class_copyMethodList(meta ? object_getClass(c) : c, &n);
        for (unsigned i = 0; i < n; i++)
            [o appendFormat:@"%s %s  %s\n", meta ? "+" : "-", sel_getName(method_getName(ms[i])), method_getTypeEncoding(ms[i]) ?: ""];
        free(ms);
    }
}
static void CC9WriteDump(void) {
    NSMutableString *o = [NSMutableString string];
    [o appendFormat:@"CCNine diagnostic - iOS %@ - %@\n", UIDevice.currentDevice.systemVersion, [NSDate date]];
    [o appendFormat:@"Methodes du geste interceptees dynamiquement : %@\n", gHooked];
    for (NSString *n in @[@"SBControlCenterController", @"SBControlCenterWindow",
                          @"CCUIModularControlCenterOverlayViewController", @"SBControlCenterSystemAgent"])
        CC9DumpClass(n.UTF8String, o);
    unsigned cnt = 0; Class *list = objc_copyClassList(&cnt);
    NSMutableArray *names = [NSMutableArray array];
    for (unsigned i = 0; i < cnt; i++) {
        const char *nm = class_getName(list[i]);
        if (strcasestr(nm, "ControlCenter") || strncmp(nm, "CCUI", 4) == 0 || strcasestr(nm, "SystemGesture"))
            [names addObject:@(nm)];
    }
    free(list);
    [names sortUsingSelector:@selector(compare:)];
    [o appendFormat:@"\n=== Classes liees au CC / aux gestes systeme ===\n%@\n", [names componentsJoinedByString:@"\n"]];
    [o writeToFile:CC9_DUMP atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

@interface CCUIModularControlCenterOverlayViewController : UIViewController @end
@interface SBControlCenterWindow : UIWindow @end

// ---------- Hooks connus (iOS 13-15, souvent encore valides) ----------
%group CCHooks
%hook SBControlCenterController
- (void)_showControlCenterGestureBeganWithGestureRecognizer:(id)gr     { CC9Route(0, gr); }
- (void)_showControlCenterGestureChangedWithGestureRecognizer:(id)gr   { CC9Route(1, gr); }
- (void)_showControlCenterGestureEndedWithGestureRecognizer:(id)gr     { CC9Route(2, gr); }
- (void)_showControlCenterGestureCancelledWithGestureRecognizer:(id)gr { CC9Route(3, gr); }
- (void)presentAnimated:(BOOL)a                                        { [[CC9Controller shared] presentAnimated:a]; }
- (void)presentAnimated:(BOOL)a completion:(void (^)(void))c           { [[CC9Controller shared] presentAnimated:a]; if (c) c(); }
- (BOOL)isPresented { return NO; }
- (BOOL)isVisible   { return NO; }
%end
%end

// ---------- FILET DE SÉCURITÉ : si le CC natif apparaît quand même ----------
// Dès que sa vue va s'afficher : on la cache, on ouvre le nôtre, on referme le natif.
%group OverlayHooks
%hook CCUIModularControlCenterOverlayViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [(UIViewController *)self view].hidden = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CC9Controller shared] presentAnimated:YES];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ CC9DismissNative(); });
    });
}
- (void)viewDidAppear:(BOOL)animated      { %orig; [(UIViewController *)self view].hidden = YES; }
- (void)viewDidLayoutSubviews             { %orig; [(UIViewController *)self view].hidden = YES; }
%end
%end

// ---------- La FENÊTRE du CC natif reste invisible en permanence (c'est elle qu'on voyait derrière) ----------
%group WindowHooks
%hook SBControlCenterWindow
- (void)setHidden:(BOOL)h      { %orig(YES); }
- (void)setAlpha:(CGFloat)a    { %orig(0.0); }
- (void)makeKeyAndVisible      { %orig; [(UIWindow *)self setHidden:YES]; [(UIWindow *)self setAlpha:0]; }
%end
%end

// Bouton Home : ferme notre CC
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
        if (!CC9GuardAllows()) { NSLog(@"[CCNine] desactive (kill-switch / crash-loop guard)"); return; }
        gHooked = [NSMutableArray array];

        dlopen("/System/Library/PrivateFrameworks/ControlCenterUI.framework/ControlCenterUI", RTLD_LAZY);
        if (!objc_getClass("SBControlCenterController")) { NSLog(@"[CCNine] SBControlCenterController introuvable"); return; }

        %init(CCHooks);
        CC9HookGestureMethods();
        if (objc_getClass("CCUIModularControlCenterOverlayViewController")) %init(OverlayHooks);
        if (objc_getClass("SBControlCenterWindow")) %init(WindowHooks);
        if (objc_getClass("SBHomeHardwareButtonActions")) %init(HomeHooks);

        // Écrit /var/mobile/Documents/CCNine_dump.txt 20 s après le démarrage (preuve que le tweak est chargé)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 20 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{ CC9WriteDump(); });
        NSLog(@"[CCNine] charge");
    }
}
