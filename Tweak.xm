#import <sys/utsname.h>
#import <substrate.h>
#import "Tweak.h"

#define UNSUPPORTED_DEVICES @[@"iPhone14,3", @"iPhone14,6", @"iPhone14,8"]
#define THRESHOLD 1.99

static CGFloat videoAspectRatio = 16/9;
CGFloat constant; // Make renderingView a bit larger since constraining to safe area leaves a gap between the notch and video
static BOOL isZoomedToFill = NO;
static BOOL isEngagementPanelVisible = NO;
static BOOL isRemoveEngagementPanelViewControllerWithIdentifierCalled = NO;

static MLHAMSBDLSampleBufferRenderingView *renderingView;
static NSLayoutConstraint *widthConstraint, *heightConstraint, *centerXConstraint, *centerYConstraint;

static BOOL DEMC_isDeviceSupported();
static void DEMC_activate();
static void DEMC_deactivate();
static void DEMC_centerRenderingView();

%group DontEatMyContent

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
    UIView *renderingViewContainer = MSHookIvar<UIView *>(playerView, "_renderingViewContainer");
    renderingView = [playerView renderingView];

    widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.widthAnchor constant:constant];
    heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.heightAnchor constant:constant];
    centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:renderingViewContainer.centerXAnchor];
    centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:renderingViewContainer.centerYAnchor];

    if (IS_COLOR_VIEWS_ENABLED) {
        playerView.backgroundColor = [UIColor blueColor];
        renderingViewContainer.backgroundColor = [UIColor greenColor];
        renderingView.backgroundColor = [UIColor redColor];
    } else {
        playerView.backgroundColor = nil;
        renderingViewContainer.backgroundColor = nil;
        renderingView.backgroundColor = [UIColor blackColor];
    }

    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];

    // Must check class since YTInlineMutedPlaybackPlayerOverlayViewController doesn't have -(BOOL)isFullscreen
    if ([activeVideoPlayerOverlay isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)] &&
        [activeVideoPlayerOverlay isFullscreen] && !isZoomedToFill && !isEngagementPanelVisible)
        DEMC_activate();

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
        DEMC_activate();
    else if (![self isCurrentVideoVertical] && ((YTPlayerView *)[self playerView]).userInteractionEnabled)
        DEMC_deactivate();
}
- (void)setPlayerViewLayout:(int)layout {
    %orig(layout);

    if (![[self activeVideoPlayerOverlay] isKindOfClass:%c(YTMainAppVideoPlayerOverlayViewController)]) return;

    switch (layout) {
    case 1: // Mini bar
        break;
    case 2:
        DEMC_deactivate();
        break;
    case 3: // Fullscreen
        if (!isZoomedToFill && !isEngagementPanelVisible) DEMC_activate();
        break;
    default:
        break;
    }
}
%end

// Pinch to zoom
%hook YTVideoFreeZoomOverlayView
- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    DEMC_deactivate();
    %orig(pinchGestureRecognizer);
}
// Detect zoom to fill
- (void)showLabelForSnapState:(NSInteger)snapState {
    if (snapState == 0) { // Original
        isZoomedToFill = NO;
        DEMC_activate();
    } else if (snapState == 1) { // Zoomed to fill
        isZoomedToFill = YES;
        // No need to deactivate constraints as it's already done in -(void)didRecognizePinch:(UIPinchGestureRecognizer *)
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
            DEMC_deactivate();
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
            DEMC_activate();
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

%end // group DontEatMyContent

%ctor {
    constant = [[NSUserDefaults standardUserDefaults] floatForKey:SAFE_AREA_CONSTANT_KEY];
    if (constant == 0) {
        constant = DEFAULT_CONSTANT;
        [[NSUserDefaults standardUserDefaults] setFloat:constant forKey:SAFE_AREA_CONSTANT_KEY];
    }
    if (IS_TWEAK_ENABLED && DEMC_isDeviceSupported()) %init(DontEatMyContent);
}

static BOOL DEMC_isDeviceSupported() {
    // Get device model identifier (e.g. iPhone14,4)
    // https://stackoverflow.com/a/11197770/19227228
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModelID = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];

    NSArray *unsupportedModelIDs = UNSUPPORTED_DEVICES;
    for (NSString *identifier in unsupportedModelIDs) {
        if ([deviceModelID isEqualToString:identifier]) {
            return NO;
        }
    }

    if ([deviceModelID containsString:@"iPhone"]) {
        if ([deviceModelID isEqualToString:@"iPhone13,1"]) {
            // iPhone 12 mini
            return YES;
        }
        NSString *modelNumber = [[deviceModelID stringByReplacingOccurrencesOfString:@"iPhone" withString:@""] stringByReplacingOccurrencesOfString:@"," withString:@"."];
        if ([modelNumber floatValue] >= 14.0) {
            // iPhone 13 series and newer
            return YES;
        } else return NO;
    } else return NO;
}

static void DEMC_activate() {
    if (videoAspectRatio < THRESHOLD) {
        DEMC_deactivate();
        return;
    }
    // NSLog(@"activate");
    DEMC_centerRenderingView();
    renderingView.translatesAutoresizingMaskIntoConstraints = NO;
    widthConstraint.active = YES;
    heightConstraint.active = YES;
}

static void DEMC_deactivate() {
    // NSLog(@"deactivate");
    renderingView.translatesAutoresizingMaskIntoConstraints = YES;
}

static void DEMC_centerRenderingView() {
    centerXConstraint.active = YES;
    centerYConstraint.active = YES;
}