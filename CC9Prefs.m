#import "CC9Prefs.h"

NSString *const CC9PrefsChanged = @"CC9PrefsChanged";
static CFStringRef const kCC9Domain = CFSTR("com.example.ccnine");

static id CC9PrefValue(CFStringRef key) {
    CFPreferencesAppSynchronize(kCC9Domain);   // relit le fichier : le panneau Réglages tourne dans un autre processus
    return CFBridgingRelease(CFPreferencesCopyAppValue(key, kCC9Domain));
}

BOOL CC9PrefReplaceCalcWithRecord(void) {
    id v = CC9PrefValue(CFSTR("replaceCalcWithRecord"));
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : NO;
}

CGFloat CC9PrefWhiten(void) {
    id v = CC9PrefValue(CFSTR("whitenPercent"));
    CGFloat pct = [v respondsToSelector:@selector(doubleValue)] ? [v doubleValue] : 30.0;
    return MAX(0.0, MIN(90.0, pct)) / 100.0;
}

static void CC9PrefsCallback(CFNotificationCenterRef c, void *o, CFNotificationName n, const void *obj, CFDictionaryRef u) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CC9PrefsChanged object:nil];
    });
}

void CC9PrefsStartObserving(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, CC9PrefsCallback,
                                        CFSTR("com.example.ccnine/prefschanged"), NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    });
}
