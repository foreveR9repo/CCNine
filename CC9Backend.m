#import "CC9Backend.h"
#import "CC9Private.h"
#import <AVFoundation/AVFoundation.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <objc/message.h>

// Récupère [Classe sharedInstance] sans lier la classe privée et sans ambiguïté de sélecteur
static id CC9Shared(const char *cls) {
    Class c = objc_getClass(cls); SEL s = @selector(sharedInstance);
    return (c && [c respondsToSelector:s]) ? ((id (*)(Class, SEL))objc_msgSend)(c, s) : nil;
}

// Journal : /var/mobile/Documents/CCNine_log.txt (lisible avec Filza)
void CC9Log(NSString *m) {
    NSString *p = @"/var/mobile/Documents/CCNine_log.txt";
    NSData *d = [[NSString stringWithFormat:@"%@  %@\n", [NSDate date], m] dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:p];
    if (!h) { [d writeToFile:p atomically:YES]; return; }
    if (h.seekToEndOfFile > 200000) { [h truncateFileAtOffset:0]; }
    [h writeData:d]; [h closeFile];
}

NSString *const CC9StateChanged = @"CC9StateChanged";

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef Boolean (*MRSendFn)(int, id);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef float (*BKSGetFn)(void);
typedef void (*BKSSetFn)(float, int);
static NSString *const kDNDClient = @"com.apple.donotdisturb.control-center.module";

@implementation CC9Backend {
    RadiosPreferences *_radios;
    CBBlueLightClient *_blue;
    MRGetInfoFn _mrInfo; MRSendFn _mrSend;
    BKSGetFn _bksGet; BKSSetFn _bksSet;
    id _dndService; id _dndAssertion; id _airDrop; BOOL _dndFlag;
}

+ (instancetype)shared {
    static CC9Backend *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [CC9Backend new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
        void *bks = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
        if (bks) { _bksGet = (BKSGetFn)dlsym(bks, "BKSDisplayBrightnessGetCurrent"); _bksSet = (BKSSetFn)dlsym(bks, "BKSDisplayBrightnessSet"); }
        CC9Log([NSString stringWithFormat:@"init: BKSGet=%d BKSSet=%d", _bksGet != NULL, _bksSet != NULL]);
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        dlopen("/System/Library/PrivateFrameworks/AppSupport.framework/AppSupport", RTLD_LAZY);
        void *mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (mr) {
            _mrInfo = (MRGetInfoFn)dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
            _mrSend = (MRSendFn)dlsym(mr, "MRMediaRemoteSendCommand");
            MRRegisterFn reg = (MRRegisterFn)dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
            if (reg) {
                reg(dispatch_get_main_queue());
                for (NSString *n in @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                                      @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"]) {
                    [[NSNotificationCenter defaultCenter] addObserverForName:n object:nil queue:NSOperationQueue.mainQueue
                        usingBlock:^(NSNotification *x) { [[NSNotificationCenter defaultCenter] postNotificationName:CC9StateChanged object:nil]; }];
                }
            }
        }
    }
    return self;
}

#pragma mark - Toggles

- (BOOL)stateFor:(CC9Toggle)t {
    @try {
        switch (t) {
            case CC9ToggleAirplane: return [self radios] ? [[self radios] airplaneMode] : NO;
            case CC9ToggleWiFi: { SBWiFiManager *m = CC9Shared("SBWiFiManager"); return m ? [m wiFiEnabled] : NO; }
            case CC9ToggleBluetooth: { BluetoothManager *m = CC9Shared("BluetoothManager"); return m ? [m powered] : NO; }
            case CC9ToggleRotation: { SBOrientationLockManager *m = CC9Shared("SBOrientationLockManager"); return m ? [m isUserLocked] : NO; }
            case CC9ToggleDND: {
                Class c = objc_getClass("DNDStateService"); if (!c) return NO;
                id svc = [c serviceForClientIdentifier:@"com.example.ccnine"];
                NSError *e = nil; id st = [svc queryCurrentStateWithError:&e];
                BOOL active = st ? [(DNDState *)st isActive] : NO;
                return active || _dndFlag;   // la requête d'état n'est pas fiable : on garde notre propre indicateur
            }
            case CC9ToggleFlashlight: {
                AVCaptureDevice *d = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                return d.hasTorch && d.torchMode == AVCaptureTorchModeOn;
            }
            case CC9ToggleNightShift: {
                if (!_blue) { Class c = objc_getClass("CBBlueLightClient"); if (c) _blue = [c new]; }
                unsigned char buf[128] = {0};
                if (_blue && [_blue getBlueLightStatus:buf]) return buf[1] != 0; // octet 1 = "enabled" (À VÉRIFIER)
                return NO;
            }
        }
    } @catch (NSException *e) { NSLog(@"[CCNine] stateFor %ld: %@", (long)t, e); }
    return NO;
}

- (RadiosPreferences *)radios {
    if (!_radios) { Class c = objc_getClass("RadiosPreferences"); if (c) _radios = [c new]; }
    return _radios;
}

- (void)toggle:(CC9Toggle)t {
    BOOL on = ![self stateFor:t];
    @try {
        switch (t) {
            case CC9ToggleAirplane: [[self radios] setAirplaneMode:on]; [[self radios] synchronize]; break;
            case CC9ToggleWiFi: [(SBWiFiManager *)CC9Shared("SBWiFiManager") setWiFiEnabled:on]; break;
            case CC9ToggleBluetooth: {
                BluetoothManager *bt = CC9Shared("BluetoothManager");
                [bt setEnabled:on]; [bt setPowered:on]; break;
            }
            case CC9ToggleRotation: {
                SBOrientationLockManager *m = CC9Shared("SBOrientationLockManager");
                on ? [m lock] : [m unlock]; break;
            }
            case CC9ToggleDND: [self setDND:on]; break;
            case CC9ToggleFlashlight: {
                AVCaptureDevice *d = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
                if (d.hasTorch && [d lockForConfiguration:nil]) {
                    if (on) [d setTorchModeOnWithLevel:1.0 error:nil]; else d.torchMode = AVCaptureTorchModeOff;
                    [d unlockForConfiguration];
                }
                break;
            }
            case CC9ToggleNightShift: [_blue setEnabled:on]; break;
        }
    } @catch (NSException *e) { NSLog(@"[CCNine] toggle %ld: %@", (long)t, e); }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:CC9StateChanged object:nil];
    });
}

- (void)setDND:(BOOL)on {
    Class sc = objc_getClass("DNDModeAssertionService"), dc = objc_getClass("DNDModeAssertionDetails");
    if (!sc || !dc) { CC9Log(@"DND: classes absentes"); return; }
    if (on) {
        NSError *e = nil;
        DNDModeAssertionService *svc = [sc serviceForClientIdentifier:kDNDClient];
        _dndService = svc;
        id det = [dc userRequestedAssertionDetailsWithIdentifier:@"com.apple.control-center.manual-toggle"
                                                  modeIdentifier:@"com.apple.donotdisturb.mode.default" lifetime:nil];
        _dndAssertion = [svc takeModeAssertionWithDetails:det error:&e];
        _dndFlag = YES;
        CC9Log([NSString stringWithFormat:@"DND ON assertion=%@ err=%@", _dndAssertion, e]);
        return;
    }
    // OFF : UNE seule méthode, celle des tweaks existants. Elle renvoie un BOOL : on le lit comme BOOL
    // (le lire comme "id" faisait retenir la valeur 1 par ARC => crash de SpringBoard => safe mode)
    _dndFlag = NO;
    SEL all = NSSelectorFromString(@"invalidateAllActiveModeAssertionsWithError:");
    for (int pass = 0; pass < 2; pass++) {
        id svc = (pass == 0) ? [sc serviceForClientIdentifier:kDNDClient] : _dndService;   // service neuf, puis celui de l'activation
        if (!svc || ![svc respondsToSelector:all]) { CC9Log([NSString stringWithFormat:@"DND OFF pass %d: indisponible", pass]); continue; }
        NSError *err = nil;
        BOOL ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(svc, all, &err);
        CC9Log([NSString stringWithFormat:@"DND OFF pass %d ok=%d err=%@", pass, ok, err]);
    }
    _dndAssertion = nil;
}

#pragma mark - Sliders

- (float)brightness { return _bksGet ? _bksGet() : UIScreen.mainScreen.brightness; }
- (void)setBrightness:(float)v {
    v = MAX(0.01f, MIN(1.f, v));
    if (_bksSet) _bksSet(v, 1);
    Class bc = objc_getClass("SBBrightnessController");           // 2e voie, au cas où
    SEL shared = NSSelectorFromString(@"sharedBrightnessController"), setter = NSSelectorFromString(@"setBrightnessLevel:");
    if (bc && [bc respondsToSelector:shared]) {
        id inst = ((id (*)(Class, SEL))objc_msgSend)(bc, shared);
        if ([inst respondsToSelector:setter]) ((void (*)(id, SEL, float))objc_msgSend)(inst, setter, v);
    }
    UIScreen.mainScreen.brightness = v;
}

- (float)volume {
    float v = 0; Class c = objc_getClass("AVSystemController");
    if (c) [[c sharedAVSystemController] getVolume:&v forCategory:@"Audio/Video"];
    return v;
}
- (void)setVolume:(float)v {
    Class c = objc_getClass("AVSystemController");
    if (c) [[c sharedAVSystemController] setVolumeTo:v forCategory:@"Audio/Video"];
}

#pragma mark - Media / Apps

- (void)sendMediaCommand:(int)cmd { if (_mrSend) _mrSend(cmd, nil); }

- (void)fetchNowPlaying:(void (^)(NSString *, NSString *, BOOL, NSTimeInterval, NSTimeInterval))cb {
    if (!_mrInfo) { cb(nil, nil, NO, 0, 0); return; }
    _mrInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        NSDictionary *d = (__bridge NSDictionary *)info;
        id t = d[@"kMRMediaRemoteNowPlayingInfoTitle"], a = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
        float rate = [d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] floatValue];
        NSTimeInterval el = [d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"] doubleValue];
        NSTimeInterval du = [d[@"kMRMediaRemoteNowPlayingInfoDuration"] doubleValue];
        id ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        if (rate > 0 && [ts isKindOfClass:NSDate.class]) el += [[NSDate date] timeIntervalSinceDate:ts] * rate;
        cb([t isKindOfClass:NSString.class] ? t : nil, [a isKindOfClass:NSString.class] ? a : nil, rate > 0, el, du);
    });
}

#pragma mark - AirDrop (Sharing.framework, privé)

- (id)airDropController {
    if (_airDrop) return _airDrop;
    dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY);
    Class c = objc_getClass("SFAirDropDiscoveryController");
    if (!c) { CC9Log(@"AirDrop: SFAirDropDiscoveryController ABSENTE"); return nil; }
    _airDrop = [c new];
    unsigned n = 0; Method *ms = class_copyMethodList(c, &n); NSMutableArray *names = [NSMutableArray array];
    for (unsigned i = 0; i < n; i++) { NSString *nm = NSStringFromSelector(method_getName(ms[i])); if ([nm.lowercaseString containsString:@"discoverable"]) [names addObject:nm]; }
    free(ms); CC9Log([NSString stringWithFormat:@"AirDrop methodes: %@", names]);
    return _airDrop;
}
- (NSInteger)airDropMode {
    id c = [self airDropController]; SEL s = NSSelectorFromString(@"discoverableMode");
    return (c && [c respondsToSelector:s]) ? ((NSInteger (*)(id, SEL))objc_msgSend)(c, s) : -1;
}
- (void)setAirDropMode:(NSInteger)mode {
    id c = [self airDropController]; SEL s = NSSelectorFromString(@"setDiscoverableMode:");
    if (c && [c respondsToSelector:s]) {
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(c, s, mode);
        CC9Log([NSString stringWithFormat:@"AirDrop mode -> %ld (relu: %ld)", (long)mode, (long)[self airDropMode]]);
    } else CC9Log(@"AirDrop: setDiscoverableMode: ABSENT");
}

- (void)launchBundleID:(NSString *)bid {
    // LSApplicationWorkspace est SYNCHRONE : depuis SpringBoard il attend... SpringBoard (lent, voire gelé).
    // FBSSystemService est asynchrone et c'est la voie native de SpringBoard.
    dlopen("/System/Library/PrivateFrameworks/FrontBoardServices.framework/FrontBoardServices", RTLD_LAZY);
    Class fbs = objc_getClass("FBSSystemService");
    SEL shared = NSSelectorFromString(@"sharedService"), open = NSSelectorFromString(@"openApplication:options:withResult:");
    if (fbs && [fbs respondsToSelector:shared]) {
        id svc = ((id (*)(Class, SEL))objc_msgSend)(fbs, shared);
        if ([svc respondsToSelector:open]) {
            ((void (*)(id, SEL, id, id, id))objc_msgSend)(svc, open, bid, @{}, nil);
            CC9Log([NSString stringWithFormat:@"launch %@ via FBSSystemService", bid]);
            return;
        }
    }
    CC9Log([NSString stringWithFormat:@"launch %@ via LaunchServices (secours, thread d'arrière-plan)", bid]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        Class c = objc_getClass("LSApplicationWorkspace");
        if (c) [[c defaultWorkspace] openApplicationWithBundleID:bid];
    });
}
@end
