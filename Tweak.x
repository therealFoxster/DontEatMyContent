#import "Tweak.h"
#import "DuoCutout.h"

static CGFloat videoAspectRatio = 16.0 / 9.0;
static BOOL isZoomedToFill = NO;
static BOOL isEngagementPanelVisible = NO;
static BOOL isEngagementPanelViewControllerRemoved = NO;
static BOOL demcIsFullscreen = NO;
static BOOL demcUserZooming = NO;
static BOOL demcDuoConstraints = NO;
static UIView *renderingView; // MLHAMSBDLSampleBufferRenderingView *
static UIView *renderingViewContainer;
static NSLayoutConstraint *widthConstraint, *heightConstraint, *centerXConstraint, *centerYConstraint;

static const double kCutoutPadding = 2.0;

static void DEMC_activateConstraints(void);
static void DEMC_deactivateConstraints(void);

static DEMCRect DEMCRectFromCG(CGRect rect) {
    return DEMCRectMake(rect.origin.x, rect.origin.y, rect.size.width, rect.size.height);
}

static BOOL DEMC_differs(CGFloat current, CGFloat next) {
    CGFloat delta = current - next;
    return delta > 0.2 || delta < -0.2;
}

static void DEMC_attach(YTPlayerView *playerView) {
    if (!playerView)
        return;
    UIView *container = nil;
    @try {
        container = [playerView valueForKey:@"_renderingViewContainer"];
    } @catch (NSException *exception) {
        return;
    }
    UIView *videoView = [playerView renderingView];
    if (videoView == renderingView && container == renderingViewContainer)
        return;
    DEMC_deactivateConstraints();
    widthConstraint = nil;
    heightConstraint = nil;
    centerXConstraint = nil;
    centerYConstraint = nil;
    renderingView = videoView;
    renderingViewContainer = container;
}

static UIScreen *DEMC_screen(UIView *view) {
    UIWindow *window = view.window;
    if (!window)
        return nil;
    UIScreen *screen = [window respondsToSelector:@selector(windowScene)] ? window.windowScene.screen : nil;
    return screen ?: window.screen;
}

static BOOL DEMC_isDuoOuter(UIView *view) {
    UIScreen *screen = DEMC_screen(view);
    if (!screen)
        return NO;
    CGSize pixels = screen.nativeBounds.size;
    if (DEMCPixelsAreDuoOuterDisplay(pixels.width, pixels.height))
        return YES;
    return DEMCSizeIsDuoOuterDisplay(screen.bounds.size.width, screen.bounds.size.height);
}

static CGRect DEMC_regionFrame(id region) {
    @try {
        id value = [region valueForKey:@"frame"];
        if ([value isKindOfClass:[NSValue class]])
            return [value CGRectValue];
    } @catch (NSException *exception) {
    }
    return CGRectNull;
}

static SEL DEMC_regionsSelector(UIView *view) {
    SEL selectors[] = {
        @selector(reservedRegionsWithKind:options:),
        @selector(reservedRegionsOfKind:options:),
    };
    for (int i = 0; i < 2; i++) {
        if ([view respondsToSelector:selectors[i]])
            return selectors[i];
    }
    return NULL;
}

static int DEMC_reservedRegions(UIView *view, DEMCRect *output, int capacity) {
    SEL selector = DEMC_regionsSelector(view);
    if (!selector)
        return 0;
    NSMethodSignature *signature = [view methodSignatureForSelector:selector];
    const char *returnType = signature.methodReturnType;
    if (signature.numberOfArguments != 4 || !returnType || returnType[0] != '@')
        return 0;

    int count = 0;
    for (NSInteger kind = 0; kind <= 1 && count < capacity; kind++) {
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.selector = selector;
        invocation.target = view;
        NSUInteger options = 0;
        [invocation setArgument:&kind atIndex:2];
        [invocation setArgument:&options atIndex:3];
        [invocation invoke];
        NSArray * __unsafe_unretained regions = nil;
        [invocation getReturnValue:&regions];
        if (![regions isKindOfClass:[NSArray class]])
            continue;
        for (id region in regions) {
            if (count >= capacity)
                break;
            CGRect frame = DEMC_regionFrame(region);
            if (CGRectIsNull(frame) || CGRectIsEmpty(frame))
                continue;
            output[count++] = DEMCRectFromCG(frame);
        }
    }
    return count;
}

static BOOL DEMC_cutout(UIView *view, DEMCRect *cutout) {
    DEMCRect regions[8];
    int count = DEMC_reservedRegions(view, regions, 8);
    DEMCRect chosen = DEMCChooseCutout(regions, count, DEMCRectFromCG(view.bounds));
    if (!(chosen.width > 0.0)) {
        UIScreen *screen = DEMC_screen(view);
        if (!screen)
            return NO;
        CGFloat scale = screen.nativeScale > 0 ? screen.nativeScale : screen.scale;
        CGSize pixels = screen.nativeBounds.size;
        DEMCRect lens = scale > 0
            ? DEMCScalePortraitLens(MIN(pixels.width, pixels.height) / scale, MAX(pixels.width, pixels.height) / scale)
            : DEMCDuoOuterLensPortraitRect();
        CGRect portrait = CGRectMake(lens.x, lens.y, lens.width, lens.height);
        CGRect converted = [view convertRect:portrait fromCoordinateSpace:screen.coordinateSpace];
        if (CGRectIsEmpty(converted) || converted.size.width < 12 || converted.size.width > 120)
            return NO;
        chosen = DEMCRectFromCG(converted);
    }
    *cutout = DEMCRectOutset(chosen, kCutoutPadding);
    return YES;
}

static void DEMC_dropConstraints(void) {
    widthConstraint.active = NO;
    heightConstraint.active = NO;
    centerXConstraint.active = NO;
    centerYConstraint.active = NO;
    widthConstraint = nil;
    heightConstraint = nil;
    centerXConstraint = nil;
    centerYConstraint = nil;
}

static void DEMC_ensureConstraints(BOOL duo) {
    if (widthConstraint && demcDuoConstraints == duo)
        return;
    DEMC_dropConstraints();
    if (!renderingView || !renderingViewContainer)
        return;
    NSLayoutDimension *widthAnchor = duo ? renderingViewContainer.widthAnchor : renderingViewContainer.safeAreaLayoutGuide.widthAnchor;
    NSLayoutDimension *heightAnchor = duo ? renderingViewContainer.heightAnchor : renderingViewContainer.safeAreaLayoutGuide.heightAnchor;
    widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:widthAnchor constant:duo ? 0 : constant];
    heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:heightAnchor constant:duo ? 0 : constant];
    centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:renderingViewContainer.centerXAnchor];
    centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:renderingViewContainer.centerYAnchor];
    demcDuoConstraints = duo;
}

static void DEMC_setConstant(NSLayoutConstraint *constraint, CGFloat value) {
    if (constraint && DEMC_differs(constraint.constant, value))
        constraint.constant = value;
}

static void DEMC_deactivateConstraints(void) {
    if (!widthConstraint || !widthConstraint.active)
        return;
    if (renderingView)
        renderingView.translatesAutoresizingMaskIntoConstraints = YES;
    widthConstraint.active = NO;
    heightConstraint.active = NO;
    centerXConstraint.active = NO;
    centerYConstraint.active = NO;
}

static void DEMC_activateConstraints(void) {
    if (!IS_ENABLED(kTweak) || !renderingView || !renderingViewContainer || CGRectIsEmpty(renderingViewContainer.bounds))
        return;

    if (DEMC_isDuoOuter(renderingViewContainer)) {
        DEMCRect cutout;
        if (!DEMC_cutout(renderingViewContainer, &cutout))
            return;
        CGRect bounds = renderingViewContainer.bounds;
        DEMCRect container = DEMCRectFromCG(bounds);
        double aspect = videoAspectRatio > 0.01 ? videoAspectRatio : (16.0 / 9.0);
        if (!DEMCRectIntersects(DEMCCenteredVideoRect(container, aspect), cutout)) {
            DEMC_deactivateConstraints();
            return;
        }
        DEMCRect video = DEMCVideoRectAvoidingCutout(container, cutout, aspect);
        if (!(video.width > 0.0)) {
            DEMC_deactivateConstraints();
            return;
        }
        DEMC_ensureConstraints(YES);
        DEMC_setConstant(widthConstraint, video.width - bounds.size.width);
        DEMC_setConstant(heightConstraint, video.height - bounds.size.height);
        DEMC_setConstant(centerXConstraint, (CGFloat)(video.x + video.width / 2.0) - CGRectGetMidX(bounds));
        DEMC_setConstant(centerYConstraint, (CGFloat)(video.y + video.height / 2.0) - CGRectGetMidY(bounds));
    } else if (videoAspectRatio < THRESHOLD && !IS_ENABLED(kEnableForAllVideos)) {
        DEMC_deactivateConstraints();
        return;
    } else {
        DEMC_ensureConstraints(NO);
        DEMC_setConstant(widthConstraint, constant);
        DEMC_setConstant(heightConstraint, constant);
    }

    if (!widthConstraint)
        return;
    renderingView.translatesAutoresizingMaskIntoConstraints = NO;
    centerXConstraint.active = YES;
    centerYConstraint.active = YES;
    widthConstraint.active = YES;
    heightConstraint.active = YES;
}

static void DEMC_refreshIfFullscreen(YTPlayerView *playerView) {
    if (!demcIsFullscreen || isZoomedToFill || isEngagementPanelVisible || demcUserZooming)
        return;
    if (playerView)
        DEMC_attach(playerView);
    DEMC_activateConstraints();
}

static void DEMC_beginPinch(void) {
    demcUserZooming = YES;
    DEMC_deactivateConstraints();
}

static void DEMC_endPinchIfFinished(UIPinchGestureRecognizer *recognizer) {
    UIGestureRecognizerState state = recognizer.state;
    if (state != UIGestureRecognizerStateCancelled && state != UIGestureRecognizerStateFailed)
        return;
    demcUserZooming = NO;
    DEMC_refreshIfFullscreen(nil);
}

%hook YTPlayerViewController
- (void)viewDidAppear:(BOOL)animated {
    YTPlayerView *playerView = [self playerView];
    DEMC_attach(playerView);
    if (IS_ENABLED(kDisableAmbientMode)) {
        playerView.backgroundColor = [UIColor blackColor];
        renderingViewContainer.backgroundColor = [UIColor blackColor];
        renderingView.backgroundColor = [UIColor blackColor];
    } else {
        playerView.backgroundColor = [UIColor blackColor];
        renderingViewContainer.backgroundColor = nil;
        renderingView.backgroundColor = nil;
    }
    if (IS_ENABLED(kTweak)) {
        if (IS_ENABLED(kColorViews)) {
            playerView.backgroundColor = [UIColor blueColor];
            renderingViewContainer.backgroundColor = [UIColor greenColor];
            renderingView.backgroundColor = [UIColor redColor];
        }
        YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];
        // Must check class since YTInlineMutedPlaybackPlayerOverlayViewController doesn't have -(BOOL)isFullscreen
        BOOL fullscreen = [activeVideoPlayerOverlay isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)] &&
            [activeVideoPlayerOverlay isFullscreen];
        demcIsFullscreen = fullscreen;
        if (fullscreen && !isZoomedToFill && !isEngagementPanelVisible)
            DEMC_refreshIfFullscreen(playerView);
        else if (!fullscreen) {
            demcUserZooming = NO;
            DEMC_deactivateConstraints();
        }
    }
    %orig;
}
// New video played
- (void)playbackController:(id)playbackController didActivateVideo:(id)video withPlaybackData:(id)playbackData {
    %orig;
    if ([self.parentViewController isKindOfClass:NSClassFromString(@"YTInlineMutedPlaybackWatchViewController")]) return;
    isEngagementPanelVisible = NO;
    isEngagementPanelViewControllerRemoved = NO;
    if ([[self activeVideoPlayerOverlay] isFullscreen]) {
        // New video played while in full screen (landscape)
        // Activate since new videos played in full screen aren't zoomed-to-fill by default
        // (i.e. the notch/Dynamic Island will cut into content when playing a new video in full screen)
        demcIsFullscreen = YES;
        DEMC_refreshIfFullscreen([self playerView]);
    } else if (![self isCurrentVideoVertical] && ((YTPlayerView *)[self playerView]).userInteractionEnabled) {
        demcIsFullscreen = NO;
        demcUserZooming = NO;
        DEMC_deactivateConstraints();
    }
}
- (void)setPlayerViewLayout:(int)layout {
    %orig;
    if (![[self activeVideoPlayerOverlay] isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)])
        return;
    switch (layout) {
    case 1: // Mini bar
        break;
    case 2:
        demcIsFullscreen = NO;
        demcUserZooming = NO;
        DEMC_deactivateConstraints();
        break;
    case 3: // Fullscreen
        demcIsFullscreen = YES;
        if (!isZoomedToFill && !isEngagementPanelVisible)
            DEMC_refreshIfFullscreen([self playerView]);
        break;
    default:
        break;
    }
}
%end

#pragma mark - Retrieve video aspect ratio

%hook YTPlayerView
- (void)setAspectRatio:(CGFloat)aspectRatio {
    %orig;
    if (aspectRatio > 0.01)
        videoAspectRatio = aspectRatio;
    DEMC_refreshIfFullscreen(self);
}
- (void)layoutSubviews {
    %orig;
    DEMC_refreshIfFullscreen(self);
}
%end

#pragma mark - Detect zoom to fill

%hook YTVideoFreeZoomOverlayView // This hook will be used if pinch to zoom is available
- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    DEMC_beginPinch();
    %orig;
    DEMC_endPinchIfFinished(pinchGestureRecognizer);
}
- (void)showLabelForSnapState:(NSInteger)snapState {
    if (snapState == 0) { // Original
        demcUserZooming = NO;
        isZoomedToFill = NO;
        DEMC_refreshIfFullscreen(nil);
    } else if (snapState == 1) { // Zoomed to fill
        demcUserZooming = NO;
        isZoomedToFill = YES;
        // No need to deactivate constraints as it's already done in -(void)didRecognizePinch:(UIPinchGestureRecognizer *)
    }
    %orig;
}
%end

%hook YTVideoZoomOverlayView // This hook will be used if pinch to zoom is unavailable
- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    DEMC_beginPinch();
    %orig;
    DEMC_endPinchIfFinished(pinchGestureRecognizer);
}
- (void)showLabelForSnapState:(NSInteger)snapState {
    if (snapState == 0) {
        demcUserZooming = NO;
        isZoomedToFill = NO;
        DEMC_refreshIfFullscreen(nil);
    } else if (snapState == 1) {
        demcUserZooming = NO;
        isZoomedToFill = YES;
    }
    %orig;
}
%end

#pragma mark - Mini bar dismiss

%hook YTWatchMiniBarViewController
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType {
    %orig;
    isZoomedToFill = NO; // YouTube undoes zoom-to-fill when mini bar is dismissed
    demcUserZooming = NO;
}
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType skipShouldDismissCheck:(BOOL)skipShouldDismissCheck {
    %orig;
    isZoomedToFill = NO;
    demcUserZooming = NO;
}
%end

#pragma mark - Engagement panels

%hook YTMainAppEngagementPanelViewController
// Engagement panel (comment, description, etc.) about to show up
- (void)viewWillAppear:(BOOL)animated {
    if ([self isPeekingSupported]) {
        // Shorts (only Shorts support peeking, I think)
    } else {
        // Everything else
        isEngagementPanelVisible = YES;
        if ([self isLandscapeEngagementPanel])
            DEMC_deactivateConstraints();
    }
    %orig;
}
%end

%hook YTEngagementPanelContainerViewController
// Engagement panel about to dismiss
- (void)notifyEngagementPanelContainerControllerWillHideFinalPanel {
    // Crashes if plays new video while in full screen causing engagement panel dismissal
    // Must check if engagement panel was dismissed because new video played
    // (i.e. if -(void)removeEngagementPanelViewControllerWithIdentifier:(id) was called prior)
    if (![self isPeekingSupported] && !isEngagementPanelViewControllerRemoved) {
        isEngagementPanelVisible = NO;
        if (([self respondsToSelector:@selector(isWatchLandscapeEngagementPanel)] ? self.watchLandscapeEngagementPanel : self.landscapeEngagementPanel) && !isZoomedToFill)
            DEMC_refreshIfFullscreen(nil);
    }
    %orig;
}
- (void)removeEngagementPanelViewControllerWithIdentifier:(id)identifier {
    // Usually called when engagement panel is open & new video is played or mini bar is dismissed
    isEngagementPanelViewControllerRemoved = YES;
    %orig;
}
%end

#pragma mark - Constructor

%ctor {
    constant = [[NSUserDefaults standardUserDefaults] floatForKey:kSafeAreaConstant];
    if (constant == 0) { // First launch probably
        constant = DEFAULT_CONSTANT;
        [[NSUserDefaults standardUserDefaults] setFloat:constant forKey:kSafeAreaConstant];
    }
    %init;
}

#pragma mark - Functions

void DEMC_showSnackBar(NSString *text) {
    YTHUDMessage *message = [%c(YTHUDMessage) messageWithText:text];
    GOOHUDManagerInternal *manager = [%c(GOOHUDManagerInternal) sharedInstance];
    [manager showMessageMainThread:message];
}

NSBundle *DEMC_getTweakBundle() {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *bundlePath = [[NSBundle mainBundle] pathForResource:@"DontEatMyContent" ofType:@"bundle"];
        if (bundlePath)
            bundle = [NSBundle bundleWithPath:bundlePath];
        else // Rootless
            bundle = [NSBundle bundleWithPath:ROOT_PATH_NS(@"/Library/Application Support/DontEatMyContent.bundle")];
    });
    return bundle;
}
