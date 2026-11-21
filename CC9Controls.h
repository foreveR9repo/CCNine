#import <UIKit/UIKit.h>
// Cherche d'abord un PNG iOS 9 dans <jbroot>/Library/Application Support/CCNine/<name>.png, sinon SF Symbol.
UIImage *CC9Icon(NSString *name, CGFloat pt);

@interface CC9RoundButton : UIControl
@property (nonatomic) BOOL on;
- (instancetype)initWithSize:(CGFloat)size radius:(CGFloat)r icon:(UIImage *)icon;
- (void)setIcon:(UIImage *)icon;
@end

@interface CC9Slider : UISlider @end
