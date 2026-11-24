#import "CC9ViewController.h"
#import "CC9Backend.h"
#import "CC9Controls.h"
#import <AVKit/AVKit.h>
#import <objc/runtime.h>

static char kBidKey;
// Cotes ABSOLUES en points, mesurées sur tes captures (capture 1 = iPhone 6s Plus 414 pt @2,007 ; capture 3 = iPhone 6 375 pt @1,056)
static const CGFloat kPanelH = 427;
static const CGFloat kPanelHLand = 250;   // paysage : panneau bas, pleine largeur, deux colonnes (toggles/luminosité/AirDrop à gauche, média/volume/raccourcis à droite)

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
    AVRoutePickerView *_routePicker; UIButton *_airDropBtn;
    UILabel *_elapsed, *_remaining; UIView *_track, *_tick; UIButton *_heart, *_share;
    NSTimeInterval _baseElapsed, _duration; CFAbsoluteTime _baseTime; NSTimer *_progressTimer;
    BOOL _land; CGSize _builtSize; CGFloat _W, _ins, _builtIns; CGPoint _airPlayCenter;
}

- (BOOL)prefersStatusBarHidden { return NO; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAllButUpsideDown; }
- (CGFloat)panelHeight { return (_land ? kPanelHLand : kPanelH) + self.view.safeAreaInsets.bottom; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;
    UIControl *catcher = [[UIControl alloc] initWithFrame:self.view.bounds];
    catcher.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [catcher addTarget:self action:@selector(dismissTapped) forControlEvents:UIControlEventTouchDown];
    [self.view addSubview:catcher];
    [self buildPanelForSize:UIScreen.mainScreen.bounds.size];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(refresh) name:CC9StateChanged object:nil];
}

// Insets latéraux (encoche) uniquement en paysage
- (CGFloat)sideInsetForSize:(CGSize)size {
    return size.width > size.height ? MAX(self.view.safeAreaInsets.left, self.view.safeAreaInsets.right) : 0;
}

// Reconstruit le panneau quand l'orientation (ou l'encoche) change
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGSize s = self.view.bounds.size;
    if (s.width < 1 || s.height < 1) return;
    CGFloat ins = [self sideInsetForSize:s];
    if (CGSizeEqualToSize(s, _builtSize) && fabs(ins - _builtIns) < 0.5) return;
    CGFloat oldPH = self.panelHeight, vh = _visibleHeight;
    BOOL wasOpen = vh >= oldPH - 1;
    [_panel removeFromSuperview]; _panel = nil; _routePicker = nil;
    [self buildPanelForSize:s];
    [self setVisibleHeight:wasOpen ? self.panelHeight : vh];
    [self refresh];
}

- (void)buildPanelForSize:(CGSize)size {
    [CC9Backend shared];   // charge CoreBrightness etc. AVANT le test de CBBlueLightClient plus bas
    CGFloat W = size.width, H = size.height;
    BOOL L = W > H;   // paysage : panneau en bas, pleine largeur
    _land = L; _builtSize = size; _W = W;
    CGFloat ins = [self sideInsetForSize:size], UW = W - 2 * ins;
    _ins = ins; _builtIns = ins;
    CGFloat (^X)(CGFloat) = ^CGFloat(CGFloat f) { return ins + f * UW; };   // fraction de la largeur utile
    CGFloat ph = L ? kPanelHLand : kPanelH;

    _panel = [[UIView alloc] initWithFrame:CGRectMake(0, H, W, ph)];
    _panel.clipsToBounds = YES;
    [self.view addSubview:_panel];

    // VRAI flou temps réel de ce qui est derrière la fenêtre (pas d'image statique)
    // Flou plein (même étalement qu'avant), simplement blanchi comme le CC iOS 9.
    static const CGFloat kWhiten = 0.30;   // voile blanc par-dessus le flou
    _blur = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight]];
    _blur.frame = _panel.bounds;
    _blur.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_panel addSubview:_blur];

    UIView *tint = [[UIView alloc] initWithFrame:_blur.bounds];
    tint.autoresizingMask = _blur.autoresizingMask;
    tint.backgroundColor = [UIColor colorWithWhite:1 alpha:kWhiten];   // blanchit le fond
    [_blur.contentView addSubview:tint];
    UIView *blue = [[UIView alloc] initWithFrame:_blur.bounds];
    blue.autoresizingMask = _blur.autoresizingMask;
    blue.backgroundColor = [UIColor colorWithRed:.45 green:.65 blue:.95 alpha:0.03];
    [_blur.contentView addSubview:blue];

    _content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, W, ph)];
    [_blur.contentView addSubview:_content];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panelPan:)];
    pan.delegate = (id<UIGestureRecognizerDelegate>)self;
    [_panel addGestureRecognizer:pan];

    // Bandes sombres (luminosité / AirDrop), cf. captures — portrait uniquement (en paysage : tuiles arrondies)
    if (!L) {
        for (NSValue *v in @[[NSValue valueWithCGRect:CGRectMake(0, 87, W, 47)], [NSValue valueWithCGRect:CGRectMake(0, 283, W, 47)]]) {
            UIView *b = [[UIView alloc] initWithFrame:v.CGRectValue];
            b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.10]; [_content addSubview:b];
        }
    }

    // Grabber + libellé d'état
    _grabber = [[UIImageView alloc] initWithImage:CC9Icon(@"chevron.compact.down", 30)];
    _grabber.tintColor = [UIColor colorWithWhite:1 alpha:.85]; _grabber.frame = CGRectMake(W/2 - 20, 3, 40, 16);
    _grabber.contentMode = UIViewContentModeCenter; [_content addSubview:_grabber];
    _status = [[UILabel alloc] initWithFrame:CGRectMake(0, 3.5, W, 20)];
    _status.textAlignment = NSTextAlignmentCenter; _status.textColor = UIColor.whiteColor;
    _status.font = [UIFont systemFontOfSize:14]; [_content addSubview:_status];

    // Ligne de toggles
    _toggles = [NSMutableArray new];
    NSArray *defs = @[@(CC9ToggleAirplane), @(CC9ToggleWiFi), @(CC9ToggleBluetooth), @(CC9ToggleDND), @(CC9ToggleRotation)];
    NSArray *icons = @[@"airplane", @"wifi", @"bluetooth", @"moon.fill", @"lock.rotation"];
    CGFloat d = L ? 44 : 46, x0 = L ? X(0.08) : 50, step = L ? (X(0.433) - X(0.08)) / 4 : (W - 2*x0) / 4, ty = L ? 46 : 50;
    for (int i = 0; i < 5; i++) {
        CC9RoundButton *b = [[CC9RoundButton alloc] initWithSize:d radius:d/2 icon:CC9Icon(icons[i], 19)];
        b.center = CGPointMake(x0 + step*i, ty); b.tag = [defs[i] integerValue];
        [b addTarget:self action:@selector(toggleTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_content addSubview:b]; [_toggles addObject:b];
    }

    // Luminosité
    CGFloat by = L ? 134 : 110;
    [self addIcon:@"sun.min.fill" size:15 at:CGPointMake(L ? X(0.06) : 36, by)];
    [self addIcon:@"sun.max.fill" size:19 at:CGPointMake(L ? X(0.45) : W - 36, by)];
    _bright = [[CC9Slider alloc] initWithFrame:L ? CGRectMake(X(0.085), by - 15, 0.345 * UW, 30) : CGRectMake(56, 95, W - 111, 30)];
    [_bright addTarget:self action:@selector(brightChanged:) forControlEvents:UIControlEventValueChanged];
    [_content addSubview:_bright];

    // Média — tailles mesurées sur tes captures : titre 15 pt, artiste 11 pt, symboles de lecture 22 pt
    UIColor *navy = [UIColor colorWithRed:.05 green:.08 blue:.22 alpha:.85];
    _title = [self labelSize:16 color:UIColor.whiteColor];
    _artist = [self labelSize:12 color:navy];
    _elapsed = [self labelSize:12 color:navy]; _elapsed.textAlignment = NSTextAlignmentLeft;
    _remaining = [self labelSize:12 color:navy]; _remaining.textAlignment = NSTextAlignmentRight;
    _track = [UIView new]; _track.backgroundColor = [UIColor colorWithRed:.05 green:.08 blue:.22 alpha:.8]; [_content addSubview:_track];
    _tick = [UIView new]; _tick.backgroundColor = UIColor.whiteColor; [_content addSubview:_tick];
    _prev = [self mediaButton:@"backward.fill" size:22 action:@selector(prevTapped)];
    _play = [self mediaButton:@"play.fill" size:22 action:@selector(playTapped)];
    _next = [self mediaButton:@"forward.fill" size:22 action:@selector(nextTapped)];
    _heart = [self mediaButton:@"heart" size:17 action:@selector(heartTapped)];
    [_heart setImage:CC9Icon(@"heart.fill", 17) forState:UIControlStateSelected];
    _share = [self mediaButton:@"square.and.arrow.up" size:17 action:@selector(noop)];

    // Volume
    CGFloat vy = L ? 134 : 255;
    [self addIcon:@"speaker.fill" size:14 at:CGPointMake(L ? X(0.546) : 38, vy)];
    [self addIcon:@"speaker.wave.3.fill" size:16 at:CGPointMake(L ? X(0.933) : W - 37, vy)];
    _vol = [[CC9Slider alloc] initWithFrame:L ? CGRectMake(X(0.568), vy - 15, 0.34 * UW, 30) : CGRectMake(57, 240, W - 113, 30)];
    [_vol addTarget:self action:@selector(volChanged:) forControlEvents:UIControlEventValueChanged];
    [_content addSubview:_vol];

    // Ligne AirDrop | AirPlay : portrait = deux moitiés séparées par un filet (capture 2) ; paysage = deux tuiles arrondies
    UIColor *adTint = [UIColor colorWithRed:.05 green:.08 blue:.22 alpha:.8];
    NSArray *halves = @[@[@"dot.radiowaves.left.and.right", @"  AirDrop"], @[@"airplay", @"  AirPlay"]];
    CGRect fr[2];
    if (L) { fr[0] = CGRectMake(X(0.042), 168, 0.246 * UW, 56); fr[1] = CGRectMake(X(0.295), 168, 0.174 * UW, 56); }
    else   { fr[0] = CGRectMake(0, 283, W / 2, 47);            fr[1] = CGRectMake(W / 2, 283, W / 2, 47); }
    for (int i = 0; i < 2; i++) {
        NSArray *hd = halves[i];
        UIButton *hb = [UIButton buttonWithType:UIButtonTypeSystem];
        hb.frame = fr[i];
        if (L) { hb.backgroundColor = [UIColor colorWithWhite:0 alpha:0.10]; hb.layer.cornerRadius = 13; hb.clipsToBounds = YES; }
        [hb setImage:CC9Icon((NSString *)hd[0], 17) forState:UIControlStateNormal];
        [hb setTitle:(NSString *)hd[1] forState:UIControlStateNormal];
        hb.titleLabel.font = [UIFont systemFontOfSize:17]; hb.tintColor = adTint;
        if (i == 0) _airDropBtn = hb;
        [hb addTarget:self action:(i == 0 ? @selector(airDropTapped) : @selector(airPlayTapped)) forControlEvents:UIControlEventTouchUpInside];
        [_content addSubview:hb];
    }
    _airPlayCenter = CGPointMake(CGRectGetMidX(fr[1]), CGRectGetMidY(fr[1]));
    if (!L) {
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(W / 2 - 0.25, 283, 0.5, 47)];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:0.3]; [_content addSubview:sep];
    }

    // Raccourcis du bas (4 en iOS 9.0-9.2, 5 avec Night Shift en 9.3)
    _shortcuts = [NSMutableArray new];
    NSArray *sc = @[@[@"flashlight.off.fill", @(CC9ToggleFlashlight)], @[@"timer", @"com.apple.mobiletimer"],
                    @[@"circle.lefthalf.filled", @(CC9ToggleNightShift)], @[@"plus.forwardslash.minus", @"com.apple.calculator"],
                    @[@"camera.fill", @"com.apple.camera"]];
    BOOL nightShift = (objc_getClass("CBBlueLightClient") != nil);
    NSMutableArray *use = [sc mutableCopy]; if (!nightShift) [use removeObjectAtIndex:2];
    NSUInteger n = use.count; CGFloat bs = L ? ((n == 4) ? 56 : 48) : ((n == 4) ? 60 : 47);
    for (NSUInteger i = 0; i < n; i++) {
        NSArray *row = use[i];
        CC9RoundButton *b = [[CC9RoundButton alloc] initWithSize:bs radius:13 icon:CC9Icon((NSString *)row[0], round(bs * 0.43))];
        if (L) b.center = CGPointMake(X(0.575) + 0.335 * UW / (n - 1) * i, 196);
        else   b.center = (n == 5) ? CGPointMake(50 + (W - 100) / 4 * i, 376) : CGPointMake(58 + (W - 116) / 3 * i, 376);
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
    CGFloat W = _W; BOOL t = _hasTrack, L = _land;
    CGFloat cx = L ? _ins + 0.745 * (W - 2 * _ins) : W / 2;   // paysage : colonne de droite
    for (UIView *x in @[_title, _artist, _elapsed, _remaining, _track, _tick, _heart, _share]) { x.transform = CGAffineTransformIdentity; x.hidden = !t; }
    CGFloat cy = L ? (t ? 102 : 82) : (t ? 227 : 207), sp = (t && !L) ? 86 : 73;   // espacement mesuré : 73 pt sans morceau (captures 1 et 3), 86 pt avec morceau (capture 2)
    for (UIButton *b in @[_prev, _play, _next, _heart, _share]) { b.transform = CGAffineTransformIdentity; b.bounds = CGRectMake(0, 0, 56, 36); }
    _prev.center = CGPointMake(cx - sp, cy); _play.center = CGPointMake(cx, cy); _next.center = CGPointMake(cx + sp, cy);
    if (!t) return;
    if (L) {
        CGFloat hw = 136;
        _title.frame = CGRectMake(cx - hw, 28, 2 * hw, 22);
        _artist.frame = CGRectMake(cx - hw, 49, 2 * hw, 18);
        _elapsed.frame = CGRectMake(cx - hw, 69, 44, 16);
        _remaining.frame = CGRectMake(cx + hw - 54, 69, 54, 16);
        _track.frame = CGRectMake(cx - hw + 48, 76, 2 * hw - 102, 2);
        _heart.center = CGPointMake(cx - 128, cy); _share.center = CGPointMake(cx + 128, cy);
        return;
    }
    _elapsed.frame = CGRectMake(27, 149.5, 44, 16);
    _remaining.frame = CGRectMake(W - 34 - 54, 149.5, 54, 16);
    _track.frame = CGRectMake(66, 156.5, W - 132, 2);
    _title.frame = CGRectMake(40, 167, W - 80, 22);
    _artist.frame = CGRectMake(40, 191, W - 80, 18);
    _heart.center = CGPointMake(29, cy); _share.center = CGPointMake(W - 30, cy);
}

static NSString *CC9Time(NSTimeInterval s) { int v = MAX(0, (int)s); return [NSString stringWithFormat:@"%d:%02d", v / 60, v % 60]; }
- (void)updateProgress {
    if (!_hasTrack) return;
    NSTimeInterval e = _baseElapsed + (_playing ? CFAbsoluteTimeGetCurrent() - _baseTime : 0);
    if (_duration > 0) e = MIN(e, _duration);
    _elapsed.text = CC9Time(e);
    _remaining.text = _duration > 0 ? [@"-" stringByAppendingString:CC9Time(_duration - e)] : @"";
    CGFloat p = _duration > 0 ? e / _duration : 0, tw = _track.bounds.size.width;
    _tick.frame = CGRectMake(_track.frame.origin.x + p * tw - 1, _track.frame.origin.y - 6.5, 2, 15);
}
// AirDrop : pas de menu — chaque appui change le mode (Off -> Contacts Only -> Everyone -> Off), l'état s'affiche sur 2 lignes
- (void)airDropTapped {
    NSInteger cur = [[CC9Backend shared] airDropMode];
    NSInteger next = (cur < 0) ? 2 : (cur + 1) % 3;
    [[CC9Backend shared] setAirDropMode:next];
    [self updateAirDropLabelWithMode:next];
}
- (void)updateAirDropLabelWithMode:(NSInteger)m {
    if (!_airDropBtn) return;
    UILabel *l = _airDropBtn.titleLabel;
    if (m < 0 || m > 2) { [_airDropBtn setTitle:@"  AirDrop" forState:UIControlStateNormal]; l.font = [UIFont systemFontOfSize:17]; return; }
    NSArray *names = @[@"Off", @"Contacts Only", @"Everyone"];
    l.numberOfLines = 2; l.textAlignment = NSTextAlignmentLeft; l.font = [UIFont systemFontOfSize:14];
    [_airDropBtn setTitle:[NSString stringWithFormat:@"  AirDrop:\n  %@", names[m]] forState:UIControlStateNormal];
}

// AirPlay : on déclenche le sélecteur de sortie système (AVRoutePickerView) via son bouton interne
- (void)airPlayTapped {
    if (!_routePicker) {
        _routePicker = [[AVRoutePickerView alloc] initWithFrame:CGRectMake(_airPlayCenter.x - 22, _airPlayCenter.y - 22, 44, 44)];
        _routePicker.alpha = 0.02; _routePicker.userInteractionEnabled = NO;
        [_content addSubview:_routePicker]; [_routePicker layoutIfNeeded];
    }
    for (UIView *sv in _routePicker.subviews) {
        if ([sv isKindOfClass:UIButton.class]) { [(UIButton *)sv sendActionsForControlEvents:UIControlEventTouchUpInside]; CC9Log(@"AirPlay: sélecteur déclenché"); return; }
    }
    CC9Log(@"AirPlay: bouton AVRoutePickerView introuvable");
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
    [self updateAirDropLabelWithMode:[b airDropMode]];
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
    CGSize vs = self.view.bounds.size; if (vs.width < 1 || vs.height < 1) vs = _builtSize;   // orientation courante de la fenêtre
    CGFloat ph = self.panelHeight, W = vs.width, H = vs.height;
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

#pragma mark - Zone de déclenchement bas-gauche (iPhone sans bouton Home)

BOOL CC9DeviceHasNoHomeButton(void) {
    static BOOL r; static dispatch_once_t o;
    dispatch_once(&o, ^{
        CGSize s = UIScreen.mainScreen.bounds.size;   // X/11/12/13/14… : plus grand côté >= 812 pt ; SE/6/7/8 (+ Plus) : <= 736 pt
        r = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPhone && MAX(s.width, s.height) >= 812;
    });
    return r;
}

static const CGFloat kTrigWidthFrac = 0.33;   // le tiers gauche du bord bas
static const CGFloat kTrigHeight = 34;        // hauteur de la zone (≈ zone de l'indicateur Home)

// Fenêtre plein écran qui ne capte QUE les touches de la zone bas-gauche : partout ailleurs les touches passent aux fenêtres du dessous
@interface CC9TriggerWindow : UIWindow @end
@implementation CC9TriggerWindow
- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)e {
    CGSize s = self.bounds.size;   // suit l'orientation (portrait ET paysage)
    return p.x >= 0 && p.x <= s.width * kTrigWidthFrac && p.y >= s.height - kTrigHeight && p.y <= s.height;
}
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { return [self pointInside:p withEvent:e] ? [super hitTest:p withEvent:e] : nil; }
@end

#pragma mark - Contrôleur

@implementation CC9Controller {
    CC9Window *_window; CC9RootViewController *_vc; CC9TriggerWindow *_trigger;
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
    [self syncWindowFrame];
    _window.windowLevel = UIWindowLevelAlert + 1000;   // au-dessus du cover sheet : À VÉRIFIER iOS 16/17
    _window.backgroundColor = UIColor.clearColor;
    _vc = [CC9RootViewController new];
    __weak typeof(self) ws = self;
    _vc.requestDismiss = ^{ [ws dismissAnimated:YES]; };
    _window.rootViewController = _vc;
    _window.hidden = YES;
    CC9Log([NSString stringWithFormat:@"fenetre CC9 creee scene=%d level=%.0f", scene != nil, _window.windowLevel]);
}

// La fenêtre doit toujours épouser l'orientation courante de la scène (sinon le panneau reste calé sur le portrait)
- (void)syncWindowFrame {
    if (!_window) return;
    CGRect r = _window.windowScene ? _window.windowScene.coordinateSpace.bounds : UIScreen.mainScreen.bounds;
    if (!CGRectEqualToRect(_window.frame, r)) _window.frame = r;
}

static void OnMain(dispatch_block_t b) { if (NSThread.isMainThread) b(); else dispatch_async(dispatch_get_main_queue(), b); }

- (void)prewarm {   // construit la fenêtre (cachée) à l'avance : la 1re ouverture n'a plus de latence
    [self installEdgeTrigger];
    OnMain(^{
        if (self->_window) return;
        [self ensureWindow]; [self->_vc loadViewIfNeeded]; [self->_vc.view layoutIfNeeded];
        CC9Log(@"prewarm ok");
    });
}

- (void)installEdgeTrigger {
    OnMain(^{
        if (self->_trigger || !CC9DeviceHasNoHomeButton()) return;
        [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
        UIWindowScene *scene = nil;
        for (UIScene *sc in UIApplication.sharedApplication.connectedScenes)
            if ([sc isKindOfClass:UIWindowScene.class]) { scene = (UIWindowScene *)sc; break; }
        CC9TriggerWindow *w = scene ? [[CC9TriggerWindow alloc] initWithWindowScene:scene] : [[CC9TriggerWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
        w.frame = UIScreen.mainScreen.bounds;
        w.windowLevel = UIWindowLevelAlert + 900;   // au-dessus des apps, sous la fenêtre du CC9 (Alert + 1000)
        w.backgroundColor = UIColor.clearColor;
        UIViewController *vc = [UIViewController new]; vc.view.backgroundColor = UIColor.clearColor;
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(triggerPan:)];
        pan.maximumNumberOfTouches = 1; pan.delegate = (id<UIGestureRecognizerDelegate>)self;
        [vc.view addGestureRecognizer:pan];
        w.rootViewController = vc; w.hidden = NO;
        self->_trigger = w;
        CC9Log(@"zone de declenchement bas-gauche installee");
    });
}
- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)g {   // uniquement un glissement vers le HAUT
    CGPoint v = [g velocityInView:nil];
    return v.y < 0 && fabs(v.y) > fabs(v.x) * 1.2;
}
- (void)triggerPan:(UIPanGestureRecognizer *)g {
    switch (g.state) {
        case UIGestureRecognizerStateBegan:   [self gestureBegan:g]; break;
        case UIGestureRecognizerStateChanged: [self gestureChanged:g]; break;
        case UIGestureRecognizerStateEnded:   [self gestureEnded:g]; break;
        case UIGestureRecognizerStateCancelled: case UIGestureRecognizerStateFailed: [self gestureCancelled:g]; break;
        default: break;
    }
}

- (CGFloat)yOf:(id)gr { return [gr respondsToSelector:@selector(locationInView:)] ? [(UIGestureRecognizer *)gr locationInView:nil].y : -1; }
- (CGFloat)vyOf:(id)gr { return [gr respondsToSelector:@selector(velocityInView:)] ? [(UIPanGestureRecognizer *)gr velocityInView:nil].y : 0; }

- (void)gestureBegan:(id)gr {
    OnMain(^{
        @try {
            self->_gen++; CC9Log(@"gestureBegan");
            [self ensureWindow]; self->_window.hidden = NO; [self syncWindowFrame];
            [self->_vc.view layoutIfNeeded];
            [self->_vc setVisibleHeight:0]; [self->_vc refresh];
        } @catch (NSException *e) { NSLog(@"[CCNine] began: %@", e); }
    });
}
- (void)gestureChanged:(id)gr {
    OnMain(^{
        if (!self->_vc) return;
        CGFloat y = [self yOf:gr]; if (y < 0) return;
        [self->_vc setVisibleHeight:self->_window.bounds.size.height - y];
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
        [self ensureWindow]; self->_window.hidden = NO; [self syncWindowFrame]; [self->_vc.view layoutIfNeeded];
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
            }   // plus aucune interception tactile
        }];
    });
}
@end
