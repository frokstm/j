#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>

@interface CCUIContentModuleContainerView : UIView
@end

@interface CCUIModuleCollectionView : UICollectionView
@end

static const void *kCC26ChromeLayerKey = &kCC26ChromeLayerKey;
static void (*CC26OriginalContainerLayout)(CCUIContentModuleContainerView *, SEL);
static void (*CC26OriginalCollectionLayout)(CCUIModuleCollectionView *, SEL);
static BOOL sCC26ContainerHookInstalled = NO;
static BOOL sCC26CollectionHookInstalled = NO;
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
    chrome.zPosition = 1.0;

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

    CGFloat shine = reduced ? 0.035 : (dark ? 0.22 : 0.30);
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

    // Draw a native CALayer border as well as the chrome rim. This stays visible even when
    // Control Center inserts an internal backdrop view above our decorative sublayer.
    view.layer.cornerRadius = radius;
    view.layer.cornerCurve = kCACornerCurveContinuous;
    view.layer.borderWidth = 1.0;
    view.layer.borderColor = edge.CGColor;
}

static void CC26StyleModule(UIView *container) {
    if (!container || !container.window) return;

    // The module container is the stable outer surface for stock and third-party modules.
    // Style it directly so the treatment does not depend on private backdrop class names.
    CC26StyleSurface(container, YES);

    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:container.subviews];
    NSUInteger next = 0;
    NSUInteger visited = 0;

    while (next < queue.count && visited++ < 400) {
        UIView *view = queue[next++];
        if (view.hidden || view.alpha < 0.01 || CGRectIsEmpty(view.bounds)) continue;

        if (CC26IsMaterialSurface(view)) {
            CC26StyleSurface(view, YES);
            // A material view's own descendants are content, not separate module surfaces.
            continue;
        }

        [queue addObjectsFromArray:view.subviews];
    }
}

static void CC26ContainerLayout(CCUIContentModuleContainerView *self, SEL cmd) {
    if (CC26OriginalContainerLayout) CC26OriginalContainerLayout(self, cmd);
    CC26StyleModule((UIView *)self);
}

static void CC26StyleModulesInCollection(UIView *collection) {
    if (!collection || !collection.window) return;
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithArray:collection.subviews];
    NSUInteger next = 0;
    NSUInteger visited = 0;
    while (next < queue.count && visited++ < 1200) {
        UIView *view = queue[next++];
        if ([NSStringFromClass(view.class) isEqualToString:@"CCUIContentModuleContainerView"]) {
            CC26StyleModule(view);
            continue;
        }
        [queue addObjectsFromArray:view.subviews];
    }
}

static void CC26CollectionLayout(CCUIModuleCollectionView *self, SEL cmd) {
    if (CC26OriginalCollectionLayout) CC26OriginalCollectionLayout(self, cmd);
    CC26StyleModulesInCollection((UIView *)self);
}

static void CC26TryInstallHook(void) {
    if (!sCC26ContainerHookInstalled) {
        Class containerClass = objc_getClass("CCUIContentModuleContainerView");
        if (containerClass) {
            MSHookMessageEx(containerClass,
                            @selector(layoutSubviews),
                            (IMP)CC26ContainerLayout,
                            (IMP *)&CC26OriginalContainerLayout);
            sCC26ContainerHookInstalled = CC26OriginalContainerLayout != NULL;
        }
    }

    if (!sCC26CollectionHookInstalled) {
        Class collectionClass = objc_getClass("CCUIModuleCollectionView");
        if (collectionClass) {
            MSHookMessageEx(collectionClass,
                            @selector(layoutSubviews),
                            (IMP)CC26CollectionLayout,
                            (IMP *)&CC26OriginalCollectionLayout);
            sCC26CollectionHookInstalled = CC26OriginalCollectionLayout != NULL;
        }
    }

    if (!sCC26ContainerHookInstalled && !sCC26CollectionHookInstalled) {
        sCC26HookAttempts++;
        NSTimeInterval delay = MIN(1.0 + (double)sCC26HookAttempts * 0.25, 8.0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{ CC26TryInstallHook(); });
    }
}

__attribute__((constructor)) static void CC26NativeGlassInit(void) {
    dispatch_async(dispatch_get_main_queue(), ^{ CC26TryInstallHook(); });
}

