#import "CC9Controls.h"
#import <dlfcn.h>

static UIColor *CC9Navy(CGFloat a) { return [UIColor colorWithRed:0.05 green:0.08 blue:0.22 alpha:a]; }

static UIImage *CC9Bluetooth(CGFloat pt) {
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(pt, pt)];
    return [[r imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGFloat s = pt; UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:CGPointMake(.27*s, .30*s)]; [p addLineToPoint:CGPointMake(.73*s, .70*s)];
        [p addLineToPoint:CGPointMake(.50*s, .90*s)]; [p addLineToPoint:CGPointMake(.50*s, .10*s)];
        [p addLineToPoint:CGPointMake(.73*s, .30*s)]; [p addLineToPoint:CGPointMake(.27*s, .70*s)];
        p.lineWidth = 2; p.lineJoinStyle = kCGLineJoinRound; p.lineCapStyle = kCGLineCapRound;
        [UIColor.blackColor setStroke]; [p stroke];
    }] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Icône AirPlay (écran + triangle), comme iOS 9
static UIImage *CC9AirPlay(CGFloat pt) {
    CGFloat k = pt / 17.0; CGSize cs = CGSizeMake(24 * k, 20 * k);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:cs];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGContextScaleCTM(ctx.CGContext, k, k);
        UIBezierPath *f = [UIBezierPath bezierPath];
        [f moveToPoint:CGPointMake(6.5, 14)]; [f addLineToPoint:CGPointMake(2, 14)]; [f addLineToPoint:CGPointMake(2, 2)];
        [f addLineToPoint:CGPointMake(22, 2)]; [f addLineToPoint:CGPointMake(22, 14)]; [f addLineToPoint:CGPointMake(17.5, 14)];
        f.lineWidth = 1.6; f.lineJoinStyle = kCGLineJoinMiter; [UIColor.blackColor setStroke]; [f stroke];
        UIBezierPath *t = [UIBezierPath bezierPath];
        [t moveToPoint:CGPointMake(12, 10)]; [t addLineToPoint:CGPointMake(6, 18.5)]; [t addLineToPoint:CGPointMake(18, 18.5)]; [t closePath];
        [UIColor.blackColor setFill]; [t fill];
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// Symboles de lecture à angles vifs, comme iOS 9 (les SF Symbols ont les coins arrondis)
static UIImage *CC9SharpGlyph(NSString *name, CGFloat pt) {
    CGFloat h = pt * 0.9;                                   // hauteur du symbole (≈ 20 pt pour pt=22)
    CGSize cs = CGSizeMake(pt * 1.4, pt * 1.2);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:cs];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        CGFloat cx = cs.width / 2, cy = cs.height / 2; UIBezierPath *p = [UIBezierPath bezierPath];
        void (^tri)(CGFloat, CGFloat, BOOL) = ^(CGFloat x, CGFloat w, BOOL right) {   // x = bord gauche, w = largeur
            if (right) { [p moveToPoint:CGPointMake(x, cy - h/2)]; [p addLineToPoint:CGPointMake(x + w, cy)]; [p addLineToPoint:CGPointMake(x, cy + h/2)]; }
            else       { [p moveToPoint:CGPointMake(x + w, cy - h/2)]; [p addLineToPoint:CGPointMake(x, cy)]; [p addLineToPoint:CGPointMake(x + w, cy + h/2)]; }
            [p closePath];
        };
        if ([name isEqualToString:@"play.fill"]) { CGFloat w = h * 0.86; tri(cx - w/2 + 1, w, YES); }
        else if ([name isEqualToString:@"pause.fill"]) {
            CGFloat bw = h * 0.28, gap = h * 0.30;
            [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cx - gap/2 - bw, cy - h/2, bw, h)]];
            [p appendPath:[UIBezierPath bezierPathWithRect:CGRectMake(cx + gap/2, cy - h/2, bw, h)]];
        }
        else { CGFloat tw = h * 0.68; BOOL fwd = [name isEqualToString:@"forward.fill"];
            tri(cx - tw, tw, fwd); tri(cx, tw, fwd); }
        [UIColor.blackColor setFill]; [p fill];
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

UIImage *CC9Icon(NSString *name, CGFloat pt) {
    static NSString *dir; static dispatch_once_t o;
    dispatch_once(&o, ^{
        // Chemin rootless indépendant du préfixe : on part de l'emplacement de notre propre dylib
        Dl_info info; if (dladdr((void *)&CC9Icon, &info) && info.dli_fname) {
            // La dylib peut être vue via .../Library/MobileSubstrate/DynamicLibraries OU .../usr/lib/TweakInject :
            // on remonte jusqu'à trouver <jbroot>/Library/Application Support/CCNine
            NSString *p = [@(info.dli_fname) stringByDeletingLastPathComponent];
            while (p.length > 1) {
                NSString *c = [p stringByAppendingPathComponent:@"Library/Application Support/CCNine"];
                if ([NSFileManager.defaultManager fileExistsAtPath:c]) { dir = c; break; }
                p = [p stringByDeletingLastPathComponent];
            }
        }
    });
    if (dir) {
        UIImage *img = [UIImage imageWithContentsOfFile:[dir stringByAppendingFormat:@"/%@.png", name]];
        if (img) return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    if ([name isEqualToString:@"bluetooth"]) return CC9Bluetooth(pt);
    if ([name isEqualToString:@"airplay"]) return CC9AirPlay(pt);
    if ([name isEqualToString:@"play.fill"] || [name isEqualToString:@"pause.fill"] ||
        [name isEqualToString:@"backward.fill"] || [name isEqualToString:@"forward.fill"]) return CC9SharpGlyph(name, pt);
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:name withConfiguration:cfg];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

@implementation CC9RoundButton { UIView *_bg; UIImageView *_icon; }
- (instancetype)initWithSize:(CGFloat)size radius:(CGFloat)r icon:(UIImage *)icon {
    if ((self = [super initWithFrame:CGRectMake(0, 0, size, size)])) {
        _bg = [[UIView alloc] initWithFrame:self.bounds];
        _bg.layer.cornerRadius = r; _bg.userInteractionEnabled = NO; [self addSubview:_bg];
        _icon = [[UIImageView alloc] initWithFrame:self.bounds];
        _icon.contentMode = UIViewContentModeCenter; _icon.userInteractionEnabled = NO; [self addSubview:_icon];
        _icon.image = icon; [self refresh];
    }
    return self;
}
- (void)setIcon:(UIImage *)icon { _icon.image = icon; }
- (void)setOn:(BOOL)on { _on = on; [self refresh]; }
- (void)setHighlighted:(BOOL)h { [super setHighlighted:h]; [self refresh]; }
- (void)refresh {
    BOOL lit = _on || self.highlighted;
    _bg.backgroundColor = lit ? [UIColor colorWithWhite:1 alpha:0.95] : [UIColor colorWithWhite:0 alpha:0.12];
    _icon.tintColor = lit ? CC9Navy(1) : CC9Navy(0.85);
}
@end

@implementation CC9Slider
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.minimumTrackTintColor = UIColor.whiteColor;
        self.maximumTrackTintColor = CC9Navy(0.8);
        UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(21, 21)];
        UIImage *thumb = [r imageWithActions:^(UIGraphicsImageRendererContext *c) {
            CGContextSetShadowWithColor(c.CGContext, CGSizeMake(0, 1), 2, [UIColor colorWithWhite:0 alpha:.3].CGColor);
            [UIColor.whiteColor setFill];
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(3, 3, 15, 15)] fill];
        }];
        [self setThumbImage:thumb forState:UIControlStateNormal];
        [self setThumbImage:thumb forState:UIControlStateHighlighted];
    }
    return self;
}
- (CGRect)trackRectForBounds:(CGRect)b { return CGRectMake(b.origin.x, CGRectGetMidY(b) - 1, b.size.width, 2); }
@end
