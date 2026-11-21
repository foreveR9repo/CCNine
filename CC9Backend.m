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

NSString *const CC9StateChanged = @"CC9StateChanged";

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef Boolean (*MRSendFn)(int, id);
typedef void (*MRRegisterFn)(dispatch_queue_t);

@implementation CC9Backend {
    RadiosPreferences *_radios;
    CBBlueLightClient *_blue;
    MRGetInfoFn _mrInfo; MRSendFn _mrSend;
}

+ (instancetype)shared {
    static CC9Backend *s; static dispatch_once_t o;
    dispatch_once(&o, ^{ s = [CC9Backend new]; });
    return s;
}

- (instancetype)init {
    if ((self = [super init])) {
        dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
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
                return st ? [(DNDState *)st isActive] : NO;
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
    if (!sc || !dc) return;
    id svc = [sc serviceForClientIdentifier:@"com.apple.donotdisturb.control-center.module"];
    NSError *e = nil;
    if (on) {
        id det = [dc userRequestedAssertionDetailsWithIdentifier:@"com.apple.control-center.manual-toggle"
                                                  modeIdentifier:@"com.apple.donotdisturb.mode.default" lifetime:nil];
        [svc takeModeAssertionWithDetails:det error:&e];
    } else {
        [svc invalidateAllActiveModeAssertionsWithError:&e];
    }
    if (e) NSLog(@"[CCNine] DND: %@", e);
}

#pragma mark - Sliders

- (float)brightness { return UIScreen.mainScreen.brightness; }
- (void)setBrightness:(float)v { UIScreen.mainScreen.brightness = MAX(0.01f, MIN(1.f, v)); }

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

- (void)fetchNowPlaying:(void (^)(NSString *, NSString *, BOOL))cb {
    if (!_mrInfo) { cb(nil, nil, NO); return; }
    _mrInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        NSDictionary *d = (__bridge NSDictionary *)info;
        NSString *t = d[@"kMRMediaRemoteNowPlayingInfoTitle"], *a = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
        float rate = [d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"] floatValue];
        cb(t, a, rate > 0);
    });
}

- (void)launchBundleID:(NSString *)bid {
    Class c = objc_getClass("LSApplicationWorkspace");
    if (c) [[c defaultWorkspace] openApplicationWithBundleID:bid];
}
@end
