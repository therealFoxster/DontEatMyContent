#import <sys/utsname.h>
#import <rootless.h>
#import "Tweak.h"

#define THRESHOLD 1.97

CGFloat constant; // Makes rendering view a bit larger since constraining to safe area leaves a gap between the notch/Dynamic Island and video
static CGFloat videoAspectRatio = 16/9;
static BOOL isZoomedToFill = NO;
static BOOL isEngagementPanelVisible = NO;
static BOOL isRemoveEngagementPanelViewControllerWithIdentifierCalled = NO;

static MLHAMSBDLSampleBufferRenderingView *renderingView;
static NSLayoutConstraint *widthConstraint, *heightConstraint, *centerXConstraint, *centerYConstraint;

static void DEMC_activateConstraints();
static void DEMC_deactivateConstraints();
static void DEMC_centerRenderingView();
void DEMC_showSnackBar(NSString *text);
NSBundle *DEMC_getTweakBundle();

%group DEMC_Tweak

// Retrieve video aspect ratio
%hook YTPlayerView
- (void)setAspectRatio:(CGFloat)aspectRatio {
    %orig(aspectRatio);
    videoAspectRatio = aspectRatio;
}
%end

%hook YTPlayerViewController
- (void)viewDidAppear:(BOOL)animated {
    YTPlayerView *playerView = [self playerView];
    UIView *renderingViewContainer = [playerView valueForKey:@"_renderingViewContainer"];
    renderingView = [playerView renderingView];

    if (IS_DISABLE_AMBIENT_MODE_ENABLED) {
        playerView.backgroundColor = [UIColor blackColor];;
        renderingViewContainer.backgroundColor = [UIColor blackColor];
        renderingView.backgroundColor = [UIColor blackColor];
    }

    if (IS_TWEAK_ENABLED) {
        widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.widthAnchor constant:constant];
        heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.heightAnchor constant:constant];
        centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:renderingViewContainer.centerXAnchor];
        centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:renderingViewContainer.centerYAnchor];

        if (IS_COLOR_VIEWS_ENABLED) {
            playerView.backgroundColor = [UIColor blueColor];
            renderingViewContainer.backgroundColor = [UIColor greenColor];
            renderingView.backgroundColor = [UIColor redColor];
        } else if (!IS_DISABLE_AMBIENT_MODE_ENABLED) {
            playerView.backgroundColor = [UIColor blackColor];
            renderingViewContainer.backgroundColor = nil;
            renderingView.backgroundColor = nil;
        }

        YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];

        // Must check class since YTInlineMutedPlaybackPlayerOverlayViewController doesn't have -(BOOL)isFullscreen
        if ([activeVideoPlayerOverlay isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)] &&
            [activeVideoPlayerOverlay isFullscreen] && !isZoomedToFill && !isEngagementPanelVisible)
            DEMC_activateConstraints();
    }

    %orig(animated);
}
// New video played
- (void)playbackController:(id)playbackController didActivateVideo:(id)video withPlaybackData:(id)playbackData {
    %orig(playbackController, video, playbackData);

    isEngagementPanelVisible = NO;
    isRemoveEngagementPanelViewControllerWithIdentifierCalled = NO;

    if ([[self activeVideoPlayerOverlay] isFullscreen])
        // New video played while in full screen (landscape)
        // Activate since new videos played in full screen aren't zoomed-to-fill by default
        // (i.e. the notch/Dynamic Island will cut into content when playing a new video in full screen)
        DEMC_activateConstraints();
    else if (![self isCurrentVideoVertical] && ((YTPlayerView *)[self playerView]).userInteractionEnabled)
        DEMC_deactivateConstraints();
}
- (void)setPlayerViewLayout:(int)layout {
    %orig(layout);

    if (![[self activeVideoPlayerOverlay] isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)]) return;

    switch (layout) {
    case 1: // Mini bar
        break;
    case 2:
        DEMC_deactivateConstraints();
        break;
    case 3: // Fullscreen
        if (!isZoomedToFill && !isEngagementPanelVisible) DEMC_activateConstraints();
        break;
    default:
        break;
    }
}
%end

// Pinch to zoom
%hook YTVideoFreeZoomOverlayView
- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    DEMC_deactivateConstraints();
    %orig(pinchGestureRecognizer);
}
// Detect zoom to fill
- (void)showLabelForSnapState:(NSInteger)snapState {
    if (snapState == 0) { // Original
        isZoomedToFill = NO;
        DEMC_activateConstraints();
    } else if (snapState == 1) { // Zoomed to fill
        isZoomedToFill = YES;
        DEMC_deactivateConstraints();
    }
    %orig(snapState);
}
%end

// Mini bar dismiss
%hook YTWatchMiniBarViewController
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType {
    %orig(velocity, gestureType);
    isZoomedToFill = NO; // YouTube undoes zoom-to-fill when mini bar is dismissed
}
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType skipShouldDismissCheck:(BOOL)skipShouldDismissCheck {
    %orig(velocity, gestureType, skipShouldDismissCheck);
    isZoomedToFill = NO;
}
%end

%hook YTMainAppEngagementPanelViewController
// Engagement panel (comment, description, etc.) about to show up
- (void)viewWillAppear:(BOOL)animated {
    if ([self isPeekingSupported]) {
        // Shorts (only Shorts support peeking, I think)
    } else {
        // Everything else
        isEngagementPanelVisible = YES;
        if ([self isLandscapeEngagementPanel]) {
            DEMC_deactivateConstraints();
        }
    }
    %orig(animated);
}
%end

%hook YTEngagementPanelContainerViewController
// Engagement panel about to dismiss
- (void)notifyEngagementPanelContainerControllerWillHideFinalPanel {
    // Crashes if plays new video while in full screen causing engagement panel dismissal
    // Must check if engagement panel was dismissed because new video played
    // (i.e. if -(void)removeEngagementPanelViewControllerWithIdentifier:(id) was called prior)
    if (![self isPeekingSupported] && !isRemoveEngagementPanelViewControllerWithIdentifierCalled) {
        isEngagementPanelVisible = NO;
        if ([self isLandscapeEngagementPanel] && !isZoomedToFill) {
            DEMC_activateConstraints();
        }
    }
    %orig;
}
- (void)removeEngagementPanelViewControllerWithIdentifier:(id)identifier {
    // Usually called when engagement panel is open & new video is played or mini bar is dismissed
    isRemoveEngagementPanelViewControllerWithIdentifierCalled = YES;
    %orig(identifier);
}
%end

%end // group DEMC_Tweak

%ctor {
    constant = [[NSUserDefaults standardUserDefaults] floatForKey:SAFE_AREA_CONSTANT_KEY];
    if (constant == 0) { // First launch probably
        constant = DEFAULT_CONSTANT;
        [[NSUserDefaults standardUserDefaults] setFloat:constant forKey:SAFE_AREA_CONSTANT_KEY];
    }
    %init(DEMC_Tweak);
}

static void DEMC_activateConstraints() {
    if (!IS_TWEAK_ENABLED) return;
    if (videoAspectRatio < THRESHOLD) {
        DEMC_deactivateConstraints();
        return;
    }
    // NSLog(@"activate");
    DEMC_centerRenderingView();
    renderingView.translatesAutoresizingMaskIntoConstraints = NO;
    widthConstraint.active = YES;
    heightConstraint.active = YES;
}

static void DEMC_deactivateConstraints() {
    if (!IS_TWEAK_ENABLED) return;
    // NSLog(@"deactivate");
    renderingView.translatesAutoresizingMaskIntoConstraints = YES;
}

static void DEMC_centerRenderingView() {
    centerXConstraint.active = YES;
    centerYConstraint.active = YES;
}

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