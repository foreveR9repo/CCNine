#import "CC9ViewController.h"
#import "CC9Backend.h"
#import "CC9Controls.h"
#import <objc/runtime.h>

static char kBidKey;
static const CGFloat kPanelH = 386;   // hauteur iOS 9 à 375 pt de large (mesurée par proportion sur tes captures)

static NSString *CC9Status(CC9Toggle t, BOOL on) {
    NSString *o = on ? @"On" : @"Off";
    switch (t) {
        case CC9ToggleAirplane:   return [@"Airplane Mode: " stringByAppendingString:o];
        case CC9ToggleWiFi:       return [@"Wi-Fi: " stringByAppendingString:o];
        case CC9ToggleBluetooth:  return [@"Bluetooth: " stringByAppendingString:o];
        case CC9ToggleDND:        return [@"Do Not Disturb: " stringByAppendingString:o];
        case CC9ToggleRotation:   return [@"Portrait Orientation Lock: " stringByAppendingString:o];
        case CC9ToggleNightShift: return on ? @"Night Shift: On Until Sunrise" : @"Night Shift: Off";
        default: return nil;
    }
}

#pragma mark - Window / root

@interface CC9Window : UIWindow @end
@implementation CC9Window @end

@interface CC9RootViewController : UIViewController
@property (nonatomic, readonly) CGFloat visibleHeight;
@property (nonatomic, readonly) CGFloat panelHeight;
@property (nonatomic, copy) void (^requestDismiss)(void);
- (void)setVisibleHeight:(CGFloat)h;
- (void)animateOpen:(BOOL)open velocity:(CGFloat)v completion:(void (^)(BOOL finished))c;
- (void)refresh;
@end

@implementation CC9RootViewController {
    UIView *_panel; UIVisualEffectView *_blur; UIView *_content;
    UILabel *_status, *_title, *_artist; UIImageView *_grabber;
    NSMutableArray<CC9RoundButton *> *_toggles, *_shortcuts;
    CC9Slider *_bright, *_vol; UIButton *_prev, *_play, *_next;
    BOOL _playing, _hasTrack;
    UILabel *_elapsed, *_remaining; UIView *_track, *_tick; UIButton *_heart, *_share;
    NSTimeInterval _baseElapsed, _duration; CFAbsoluteTime _baseTime; NSTimer *_progressTimer;
}

- (BOOL)prefersStatusBarHidden { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (CGFloat)panelHeight { return kPanelH + self.view.safeAreaInsets.bottom; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    UIControl *catcher = [[UIControl alloc] initWithFrame:self.view.bounds];
    catcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [catcher addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:catcher];
    [self buildPanel];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:CC9StateChanged object:nil];
}

- (void)buildPanel {
    [CC9Backend shared];   // charge CoreBrightness etc. AVANT le test de CBBlueLightClient plus bas
    CGRect sb = UIScreen.mainScreen.bounds;   // la vue n'est pas encore dimensionnée dans viewDidLoad
    CGFloat W = sb.size.width, H = sb.size.height;
    _panel = [[UIView alloc] initWithFrame:CGRectMake(0, H, W, kPanelH)];
    _panel.clipsToBounds = YES;
    [self.view addSubview:_panel];

    // VRAI flou temps réel de ce qui est derrière la fenêtre (pas d'image statique)
    _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleLight]];
    _blur.frame = _panel.bounds;
    _blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_panel addSubview:_blur];
    UIView *tint = [[UIView alloc] initWithFrame:_blur.bounds];
    tint.autoresizingMask = _blur.autoresizingMask;
    tint.backgroundColor = [UIColor colorWithRed:.45 green:.65 blue:.95 alpha:0.10];
    [_blur.contentView addSubview:tint];

    _content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, kPanelH)];
    [_blur.contentView addSubview:_content];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panelPan:)];
    pan.delegate = (id<UIGestureRecognizerDelegate>)self;
    [_panel addGestureRecognizer:pan];

    // Bandes sombres (luminosité / AirDrop), cf. captures
    for (NSValue *v in @[[NSValue valueWithCGRect:CGRectMake(0, 80, W, 42)], [NSValue valueWithCGRect:CGRectMake(0, 256, W, 42)]]) {
        UIView *b = [[UIView alloc] initWithFrame:v.CGRectValue];
        b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.10]; [_content addSubview:b];
    }

    // Grabber + libellé d'état
    _grabber = [[UIImageView alloc] initWithImage:CC9Icon(@"chevron.compact.down", 22)];
    _grabber.tintColor = [UIColor colorWithWhite:1 alpha:.85]; _grabber.frame = CGRectMake(W/2 - 18, 2, 36, 16);
    _grabber.contentMode = UIViewContentModeCenter; [_content addSubview:_grabber];
    _status = [[UILabel alloc] initWithFrame:CGRectMake(0, 2, W, 20)];
    _status.textAlignment = NSTextAlignmentCenter; _status.textColor = UIColor.whiteColor;
    _status.font = [UIFont systemFontOfSize:15]; [_content addSubview:_status];

    // Ligne de toggles
    _toggles = [NSMutableArray new];
    NSArray *defs = @[@(CC9ToggleAirplane), @(CC9ToggleWiFi), @(CC9ToggleBluetooth), @(CC9ToggleDND), @(CC9ToggleRotation)];
    NSArray *icons = @[@"airplane", @"wifi", @"bluetooth", @"moon.fill", @"lock.rotation"];
    CGFloat d = 43, m = 29, step = (W - 2*m - d) / 4;
    for (int i = 0; i < 5; i++) {
        CC9RoundButton *b = [[CC9RoundButton alloc] initWithSize:d radius:d/2 icon:CC9Icon(icons[i], 19)];
        b.center = CGPointMake(m + d/2 + step*i, 46); b.tag = [defs[i] integerValue];
        [b addTarget:self action:@selector(toggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_content addSubview:b]; [_toggles addObject:b];
    }

    // Luminosité
    [self addIcon:@"sun.min.fill" size:13 at:CGPointMake(22, 101)];
    [self addIcon:@"sun.max.fill" size:18 at:CGPointMake(W - 22, 101)];
    _bright = [[CC9Slider alloc] initWithFrame:CGRectMake(46, 86, W - 92, 30)];
    [_bright addTarget:self action:@selector(brightChanged:) forControlEvents:UIControlEventValueChanged];
    [_content addSubview:_bright];

    // Média — tailles mesurées sur tes captures : titre 15 pt, artiste 11 pt, symboles de lecture 22 pt
    UIColor *navy = [UIColor colorWithRed:.05 green:.08 blue:.22 alpha:.85];
    _title = [self labelSize:15 color:UIColor.whiteColor];
    _artist = [self labelSize:11 color:navy];
    _elapsed = [self labelSize:11 color:navy]; _elapsed.textAlignment = NSTextAlignmentLeft;
    _remaining = [self labelSize:11 color:navy]; _remaining.textAlignment = NSTextAlignmentRight;
    _track = [UIView new]; _track.backgroundColor = [UIColor colorWithRed:.05 green:.08 blue:.22 alpha:.8]; [_content addSubview:_track];
    _tick = [UIView new]; _tick.backgroundColor = UIColor.whiteColor; [_content addSubview:_tick];
    _prev = [self mediaButton:@"backward.fill" size:22 action:@selector(prevTapped)];
    _play = [self mediaButton:@"play.fill" size:22 action:@selector(playTapped)];
    _next = [self mediaButton:@"forward.fill" size:22 action:@selector(nextTapped)];
    _heart = [self mediaButton:@"heart" size:17 action:@selector(heartTapped)];
    [_heart setImage:CC9Icon(@"heart.fill", 17) forState:UIControlStateSelected];
    _share = [self mediaButton:@"square.and.arrow.up" size:17 action:@selector(noop)];

    // Volume
    [self addIcon:@"speaker.fill" size:13 at:CGPointMake(28, 231)];
    [self addIcon:@"speaker.wave.3.fill" size:15 at:CGPointMake(W - 28, 231)];
    _vol = [[CC9Slider alloc] initWithFrame:CGRectMake(52, 216, W - 104, 30)];
    [_vol addTarget:self action:@selector(volChanged:) forControlEvents:UIControlEventValueChanged];
    [_content addSubview:_vol];

    // Ligne AirDrop (non fonctionnelle : voir notes)
    UIButton *ad = [UIButton buttonWithType:UIButtonTypeSystem];
    ad.frame = CGRectMake(0, 256, W, 42);
    [ad setImage:CC9Icon(@"dot.radiowaves.left.and.right", 17) forState:UIControlStateNormal];
    [ad setTitle:@"  AirDrop" forState:UIControlStateNormal];
    ad.titleLabel.font = [UIFont systemFontOfSize:17]; ad.tintColor = [UIColor colorWithRed:.05 green:.08 blue:.22 alpha:.8];
    [_content addSubview:ad];

    // Raccourcis du bas (4 en iOS 9.0-9.2, 5 avec Night Shift en 9.3)
    _shortcuts = [NSMutableArray new];
    NSArray *sc = @[@[@"flashlight.off.fill", @(CC9ToggleFlashlight)], @[@"timer", @"com.apple.mobiletimer"],
                    @[@"circle.lefthalf.filled", @(CC9ToggleNightShift)], @[@"plus.forwardslash.minus", @"com.apple.calculator"],
                    @[@"camera.fill", @"com.apple.camera"]];
    BOOL nightShift = (objc_getClass("CBBlueLightClient") != nil);
    NSMutableArray *use = [sc mutableCopy]; if (!nightShift) [use removeObjectAtIndex:2];
    NSUInteger n = use.count; CGFloat sz = (n == 4) ? 54 : 48, mm = 29;
    for (NSUInteger i = 0; i < n; i++) {
        NSArray *row = use[i];
        CC9RoundButton *b = [[CC9RoundButton alloc] initWithSize:sz radius:13 icon:CC9Icon((NSString *)row[0], 21)];
        b.center = CGPointMake(mm + sz/2 + (W - 2*mm - sz)/(n - 1) * i, 340);
        id key = row[1];
        b.tag = [key isKindOfClass:NSNumber.class] ? [key integerValue] : 0;
        if (![key isKindOfClass:NSNumber.class]) objc_setAssociatedObject(b, &kBidKey, key, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [b addTarget:self action:@selector(shortcutTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_content addSubview:b]; [_shortcuts addObject:b];
    }
    [self layoutMedia];
}

- (void)addIcon:(NSString *)n size:(CGFloat)s at:(CGPoint)c {
    UIImageView *v = [[UIImageView alloc] initWithImage:CC9Icon(n, s)];
    v.tintColor = [UIColor colorWithRed:.05 green:.08 blue:.22 alpha:.85]; v.center = c; [_content addSubview:v];
}
- (UIButton *)mediaButton:(NSString *)n size:(CGFloat)pt action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom]; b.frame = CGRectMake(0, 0, 56, 36);
    [b setImage:CC9Icon(n, pt) forState:UIControlStateNormal];
    b.imageView.contentMode = UIViewContentModeCenter;
    b.tintColor = [UIColor colorWithRed:.03 green:.04 blue:.12 alpha:1];
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside]; [_content addSubview:b]; return b;
}
- (UILabel *)labelSize:(CGFloat)pt color:(UIColor *)c {
    UILabel *l = [UILabel new]; l.font = [UIFont systemFontOfSize:pt]; l.textColor = c; l.textAlignment = NSTextAlignmentCenter;
    l.numberOfLines = 1; l.adjustsFontSizeToFitWidth = YES; l.minimumScaleFactor = 0.7; l.adjustsFontForContentSizeCategory = NO;
    [_content addSubview:l]; return l;
}

// Deux états, d'après tes captures :
//  sans morceau  (capture 1/3) : contrôles à y=188, espacement .318/.5/.672
//  avec morceau  (capture 2)   : scrubber 143, titre 162, artiste 181, contrôles 207 (+ ♡ et partager), espacement .285/.5/.706
- (void)layoutMedia {
    CGFloat W = UIScreen.mainScreen.bounds.size.width; BOOL t = _hasTrack;
    for (UIView *v in @[_title, _artist, _elapsed, _remaining, _track, _tick, _heart, _share]) { v.transform = CGAffineTransformIdentity; v.hidden = !t; }
    CGFloat cy = t ? 207 : 188, lx = t ? 0.285 : 0.318, rx = t ? 0.706 : 0.672;
    for (UIButton *b in @[_prev, _play, _next, _heart, _share]) { b.transform = CGAffineTransformIdentity; b.bounds = CGRectMake(0, 0, 56, 36); }
    _prev.center = CGPointMake(W * lx, cy); _play.center = CGPointMake(W * 0.5, cy); _next.center = CGPointMake(W * rx, cy);
    if (!t) return;
    _elapsed.frame = CGRectMake(25, 135, 44, 16);
    _remaining.frame = CGRectMake(W - 30 - 54, 135, 54, 16);
    _track.frame = CGRectMake(60, 142, W - 123, 2);
    _title.frame = CGRectMake(40, 152, W - 80, 20);
    _artist.frame = CGRectMake(40, 173, W - 80, 16);
    _heart.center = CGPointMake(27, cy); _share.center = CGPointMake(W - 31, cy);
}

static NSString *CC9Time(NSTimeInterval s) { int v = MAX(0, (int)s); return [NSString stringWithFormat:@"%d:%02d", v / 60, v % 60]; }
- (void)updateProgress {
    if (!_hasTrack) return;
    NSTimeInterval e = _baseElapsed + (_playing ? CFAbsoluteTimeGetCurrent() - _baseTime : 0);
    if (_duration > 0) e = MIN(e, _duration);
    _elapsed.text = CC9Time(e);
    _remaining.text = _duration > 0 ? [@"-" stringByAppendingString:CC9Time(_duration - e)] : @"";
    CGFloat p = _duration > 0 ? e / _duration : 0, tw = _track.bounds.size.width;
    _tick.frame = CGRectMake(_track.frame.origin.x + p * tw - 1, 136, 2, 14);
}
- (void)heartTapped { _heart.selected = !_heart.selected; }
- (void)noop {}

#pragma mark - Actions

- (void)toggleTapped:(CC9RoundButton *)b {
    CC9Toggle t = (CC9Toggle)b.tag;
    BOOL willBeOn = ![[CC9Backend shared] stateFor:t];
    [[CC9Backend shared] toggle:t];
    b.on = willBeOn;   // retour visuel immédiat
    NSString *s = CC9Status(t, willBeOn);
    if (s) [self showStatus:s];
}
- (void)shortcutTapped:(CC9RoundButton *)b {
    NSString *bid = objc_getAssociatedObject(b, &kBidKey);
    if (bid) { if (self.requestDismiss) self.requestDismiss(); [[CC9Backend shared] launchBundleID:bid]; }
    else {
        CC9Toggle t = (CC9Toggle)b.tag;
        BOOL willBeOn = ![[CC9Backend shared] stateFor:t];
        [[CC9Backend shared] toggle:t]; b.on = willBeOn;
        NSString *s = CC9Status(t, willBeOn); if (s) [self showStatus:s];
    }
}
- (void)brightChanged:(UISlider *)s { [[CC9Backend shared] setBrightness:s.value]; }
- (void)volChanged:(UISlider *)s { [[CC9Backend shared] setVolume:s.value]; }
- (void)prevTapped { [[CC9Backend shared] sendMediaCommand:5]; }
- (void)playTapped { [[CC9Backend shared] sendMediaCommand:2]; }
- (void)nextTapped { [[CC9Backend shared] sendMediaCommand:4]; }
- (void)dismissTapped { if (self.requestDismiss) self.requestDismiss(); }

- (void)showStatus:(NSString *)s {
    _status.text = s; _grabber.hidden = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideStatus) object:nil];
    [self performSelector:@selector(hideStatus) withObject:nil afterDelay:2.0];
}
- (void)hideStatus { _status.text = nil; _grabber.hidden = NO; }

- (void)refresh {
    CC9Backend *b = [CC9Backend shared];
    for (CC9RoundButton *t in _toggles) t.on = [b stateFor:(CC9Toggle)t.tag];
    for (CC9RoundButton *s in _shortcuts) if (s.tag) s.on = [b stateFor:(CC9Toggle)s.tag];
    if (!_bright.isTracking) _bright.value = b.brightness;
    if (!_vol.isTracking) _vol.value = b.volume;
    __weak typeof(self) ws = self;
    [b fetchNowPlaying:^(NSString *t, NSString *a, BOOL playing, NSTimeInterval el, NSTimeInterval du) {
        CC9RootViewController *s = ws; if (!s) return;
        s->_hasTrack = t.length > 0; s->_title.text = t; s->_artist.text = a; s->_playing = playing;
        s->_baseElapsed = el; s->_duration = du; s->_baseTime = CFAbsoluteTimeGetCurrent();
        [s->_play setImage:CC9Icon(playing ? @"pause.fill" : @"play.fill", 22) forState:UIControlStateNormal];
        s->_prev.alpha = s->_next.alpha = (s->_hasTrack ? 1 : 0.4);
        [s layoutMedia]; [s updateProgress];
        if (playing && !s->_progressTimer) {
            s->_progressTimer = [NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(NSTimer *tm) {
                CC9RootViewController *x = ws; if (!x) { [tm invalidate]; return; } [x updateProgress];
            }];
        }
    }];
}

#pragma mark - Geste vertical sur le panneau (fermeture)

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)g {
    CGPoint v = [g velocityInView:_panel];
    return fabs(v.y) > fabs(v.x) * 1.5 && v.y > 0; // uniquement vers le bas
}
- (void)panelPan:(UIPanGestureRecognizer *)g {
    CGFloat dy = [g translationInView:self.view].y;
    switch (g.state) {
        case UIGestureRecognizerStateChanged: [self setVisibleHeight:self.panelHeight - MAX(0, dy)]; break;
        case UIGestureRecognizerStateEnded: case UIGestureRecognizerStateCancelled: {
            CGFloat vy = [g velocityInView:self.view].y;
            BOOL close = vy > 300 || _visibleHeight < self.panelHeight * 0.6;
            if (close && self.requestDismiss) self.requestDismiss(); else [self animateOpen:YES velocity:vy completion:nil];
        } break;
        default: break;
    }
}

#pragma mark - Positionnement

- (void)setVisibleHeight:(CGFloat)h {
    CGFloat ph = self.panelHeight, W = UIScreen.mainScreen.bounds.size.width, H = UIScreen.mainScreen.bounds.size.height;
    if (h > ph) h = ph + (h - ph) * 0.2; // élastique vers le haut
    h = MAX(0, h); _visibleHeight = h;
    _panel.frame = CGRectMake(0, H - h, W, MAX(h, ph));   // on anime la position, jamais l'alpha de l'effect view
}
- (void)animateOpen:(BOOL)open velocity:(CGFloat)v completion:(void (^)(BOOL finished))c {
    [UIView animateWithDuration:0.32 delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{ [self setVisibleHeight:open ? self.panelHeight : 0]; }
                     completion:^(BOOL f) { if (c) c(f); }];
}
@end

#pragma mark - Contrôleur

@implementation CC9Controller {
    CC9Window *_window; CC9RootViewController *_vc;
    NSUInteger _gen;   // change à chaque (ré)ouverture : une ancienne fermeture ne peut plus cacher la fenêtre
}
+ (instancetype)shared { static CC9Controller *s; static dispatch_once_t o; dispatch_once(&o, ^{ s = [CC9Controller new]; }); return s; }

- (BOOL)isOpen { return _window && !_window.hidden && _vc.visibleHeight > 0.5; }

- (void)ensureWindow {
    if (_window) return;
    UIWindowScene *scene = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes)
        if ([s isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)s; break; }
    _window = scene ? [[CC9Window alloc] initWithWindowScene:scene] : [[CC9Window alloc] initWithFrame:UIScreen.mainScreen.bounds];
    _window.frame = UIScreen.mainScreen.bounds;
    _window.windowLevel = UIWindowLevelAlert + 1000;   // au-dessus du cover sheet : À VÉRIFIER iOS 16/17
    _window.backgroundColor = UIColor.clearColor;
    _vc = [CC9RootViewController new];
    __weak typeof(self) ws = self;
    _vc.requestDismiss = ^{ [ws dismissAnimated:YES]; };
    _window.rootViewController = _vc;
    _window.hidden = YES;
    CC9Log([NSString stringWithFormat:@"fenetre CC9 creee scene=%d level=%.0f", scene != nil, _window.windowLevel]);
}

static void OnMain(dispatch_block_t b) { if (NSThread.isMainThread) b(); else dispatch_async(dispatch_get_main_queue(), b); }

- (CGFloat)yOf:(id)gr { return [gr respondsToSelector:@selector(locationInView:)] ? [(UIGestureRecognizer *)gr locationInView:nil].y : -1; }
- (CGFloat)vyOf:(id)gr { return [gr respondsToSelector:@selector(velocityInView:)] ? [(UIPanGestureRecognizer *)gr velocityInView:nil].y : 0; }

- (void)gestureBegan:(id)gr {
    OnMain(^{
        @try {
            self->_gen++; CC9Log(@"gestureBegan");
            [self ensureWindow]; self->_window.hidden = NO;
            [self->_vc.view layoutIfNeeded];
            [self->_vc setVisibleHeight:0]; [self->_vc refresh];
        } @catch (NSException *e) { NSLog(@"[CCNine] began: %@", e); }
    });
}
- (void)gestureChanged:(id)gr {
    OnMain(^{
        if (!self->_vc) return;
        CGFloat y = [self yOf:gr]; if (y < 0) return;
        [self->_vc setVisibleHeight:UIScreen.mainScreen.bounds.size.height - y];
    });
}
- (void)gestureEnded:(id)gr {
    OnMain(^{
        if (!self->_vc) return;
        CGFloat vy = [self vyOf:gr], ph = self->_vc.panelHeight;
        BOOL open = vy < -250 ? YES : (vy > 250 ? NO : self->_vc.visibleHeight > ph * 0.5);
        open ? [self->_vc animateOpen:YES velocity:vy completion:nil] : [self dismissAnimated:YES];
    });
}
- (void)gestureCancelled:(id)gr { [self dismissAnimated:YES]; }

- (void)presentAnimated:(BOOL)animated {
    OnMain(^{
        if (self.isOpen) return;
        self->_gen++; CC9Log(@"present");
        [self ensureWindow]; self->_window.hidden = NO; [self->_vc.view layoutIfNeeded];
        [self->_vc setVisibleHeight:0]; [self->_vc refresh];
        [self->_vc animateOpen:YES velocity:0 completion:nil];
    });
}
- (void)dismissAnimated:(BOOL)animated {
    OnMain(^{
        if (!self->_window) return;
        NSUInteger g = self->_gen;
        [self->_vc animateOpen:NO velocity:0 completion:^(BOOL finished) {
            // une ouverture plus récente (gen différent) annule le masquage ; sinon on cache TOUJOURS la fenêtre
            if (g == self->_gen && self->_vc.visibleHeight < 1) {
                self->_window.hidden = YES;
                self->_window.rootViewController = nil;
                self->_window = nil; self->_vc = nil;
            }   // plus aucune interception tactile
        }];
    });
}
@end
