#import <UIKit/UIKit.h>
// Réglages lus dans /var/mobile/Library/Preferences/com.example.ccnine.plist (écrits par le panneau Réglages > CCNine)
extern NSString *const CC9PrefsChanged;          // notification interne postée sur le thread principal quand un réglage change
BOOL CC9PrefReplaceCalcWithRecord(void);         // remplace le bouton Calculatrice par l'enregistrement d'écran
CGFloat CC9PrefWhiten(void);                     // opacité du voile blanc sur le flou : 0.0 ... 0.9 (défaut 0.30)
void CC9PrefsStartObserving(void);
