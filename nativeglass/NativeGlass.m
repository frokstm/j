#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

@interface CCUIContentModuleContainerView : UIView
@end

static const void *kCC26ChromeLayerKey = &kCC26ChromeLayerKey;
static void (*CC26OriginalContainerLayout)(CCUIContentModuleContainerView *, SEL);
static BOOL sCC26HookInstalled = NO;
static NSUInteger sCC26HookAttempts = 0;

static BOOL CC26IsMaterialSurface(UIView *view) {
    if (!view || view.hidden || view.alpha < 0.01) return NO;

    NSString *name = NSStringFromClass(view.class);
    if ([view isKindOfClass:UIVisualEffectView.class]) {
        UIView *parent = view.superview;
        if (!parent || CGRectIsEmpty(parent.bounds)) return NO;
        CGFloat viewArea = CGRectGetWidth(view.bounds) * CGRectGetHeight(view.bounds);
        CGFloat parentArea = CGRectGetWidth(parent.bounds) * CGRectGetHeight(parent.bounds);
        // Ignore small effect views used inside media artwork and other module content.
        return parentArea > 0.0 && viewArea / parentArea >= 0.72;
    }
    return [name containsString:@"MTMaterialView"] ||
           [name containsString:@"ModuleBackground"] ||
           [name containsString:@"BackdropView"];
}

static CGFloat CC26CornerRadius(UIView *view) {
    CGFloat radius = view.layer.cornerRadius;
    if (radius < 4.0 && view.superview.layer.cornerRadius >= 4.0) {
        radius = view.superview.layer.cornerRadius;
    }
    if (radius < 4.0) radius = 16.0;
    return MIN(radius, MIN(CGRectGetWidth(view.bounds), CGRectGetHeight(view.bounds)) * 0.5);
}

static CALayer *CC26ChromeLayer(UIView *view) {
    CALayer *chrome = objc_getAssociatedObject(view, kCC26ChromeLayerKey);
    if (chrome) return chrome;

    chrome = [CALayer layer];
    chrome.name = @"ControlCenter26.GlassChrome";
    chrome.masksToBounds = YES;

    CAGradientLayer *sheen = [CAGradientLayer layer];
    sheen.name = @"ControlCenter26.GlassSheen";
    sheen.startPoint = CGPointMake(0.5, 0.0);
    sheen.endPoint = CGPointMake(0.5, 1.0);
    sheen.locations = @[ @0.0, @0.18, @0.68, @1.0 ];
    [chrome addSublayer:sheen];

    CAShapeLayer *rim = [CAShapeLayer layer];
    rim.name = @"ControlCenter26.GlassRim";
    rim.fillColor = UIColor.clearColor.CGColor;
    rim.lineWidth = 1.0;
    [chrome addSublayer:rim];

    [view.layer addSublayer:chrome];
    objc_setAssociatedObject(view, kCC26ChromeLayerKey, chrome, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return chrome;
}

static void CC26StyleSurface(UIView *view, BOOL useSheen) {
    if (!view || CGRectIsEmpty(view.bounds)) return;

    CGFloat radius = CC26CornerRadius(view);
    CALayer *chrome = CC26ChromeLayer(view);
    chrome.frame = view.bounds;
    chrome.cornerRadius = radius;

    CAGradientLayer *sheen = (CAGradientLayer *)chrome.sublayers.firstObject;
    CAShapeLayer *rim = (CAShapeLayer *)chrome.sublayers.lastObject;
    BOOL reduced = UIAccessibilityIsReduceTransparencyEnabled();
    BOOL dark = view.traitCollection.userInterfaceStyle != UIUserInterfaceStyleLight;

    CGFloat shine = reduced ? 0.025 : (dark ? 0.13 : 0.24);
    UIColor *mid = [UIColor colorWithWhite:1.0 alpha:reduced ? 0.008 : (dark ? 0.025 : 0.045)];
    UIColor *edge = [UIColor colorWithWhite:(dark ? 1.0 : 0.0)
                                      alpha:(dark ? 0.19 : 0.10)];
    sheen.hidden = !useSheen;
    sheen.frame = chrome.bounds;
    sheen.cornerRadius = radius;
    sheen.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:shine].CGColor,
        (id)mid.CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:reduced ? 0.0 : 0.012].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0.0].CGColor
    ];

    CGRect rimRect = CGRectInset(chrome.bounds, 0.5, 0.5);
    rim.frame = chrome.bounds;
    rim.path = [UIBezierPath bezierPathWithRoundedRect:rimRect
                                          cornerRadius:MAX(0.0, radius - 0.5)].CGPath;
    rim.strokeColor = edge.CGColor;
}

static void CC26StyleModule(UIView *container) {
    if (!container || !container.window) return;

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:container.subviews];
    NSUInteger visited = 0;
    NSUInteger styled = 0;

    while (queue.count && visited++ < 240) {
        UIView *view = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (view.hidden || view.alpha < 0.01 || CGRectIsEmpty(view.bounds)) continue;

        if (CC26IsMaterialSurface(view)) {
            CC26StyleSurface(view, YES);
            styled++;
            // A material view's own descendants are content, not separate module surfaces.
            continue;
        }

        [queue addObjectsFromArray:view.subviews];
    }

    // A few stock and third-party modules draw their background directly on the container.
    // Give those a subtle rim while leaving their controls and hit testing untouched.
    if (styled == 0) CC26StyleSurface(container, NO);
}

static void CC26ContainerLayout(CCUIContentModuleContainerView *self, SEL cmd) {
    if (CC26OriginalContainerLayout) CC26OriginalContainerLayout(self, cmd);
    CC26StyleModule((UIView *)self);
}

static void CC26TryInstallHook(void) {
    if (sCC26HookInstalled) return;
    Class containerClass = objc_getClass("CCUIContentModuleContainerView");
    if (containerClass) {
        MSHookMessageEx(containerClass,
                        @selector(layoutSubviews),
                        (IMP)CC26ContainerLayout,
                        (IMP *)&CC26OriginalContainerLayout);
        sCC26HookInstalled = CC26OriginalContainerLayout != NULL;
    }

    if (!sCC26HookInstalled && sCC26HookAttempts++ < 60) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{ CC26TryInstallHook(); });
    }
}

__attribute__((constructor)) static void CC26NativeGlassInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ CC26TryInstallHook(); });
}

