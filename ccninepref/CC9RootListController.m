#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

@interface CC9RootListController : PSListController
@end

@implementation CC9RootListController

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    return _specifiers;
}

// Bouton « Reset to defaults »
- (void)resetDefaults {
    CFStringRef dom = CFSTR("com.example.ccnine");
    CFPreferencesSetAppValue(CFSTR("replaceCalcWithRecord"), NULL, dom);
    CFPreferencesSetAppValue(CFSTR("whitenPercent"), NULL, dom);
    CFPreferencesAppSynchronize(dom);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.example.ccnine/prefschanged"), NULL, NULL, YES);
    [self reloadSpecifiers];
}

@end
