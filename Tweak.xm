#import <sys/utsname.h>
#import <substrate.h>
#import "Tweak.h"

#define UNSUPPORTED_DEVICES @[@"iPhone14,3", @"iPhone14,6", @"iPhone14,8"]
#define THRESHOLD 1.99

static double videoAspectRatio = 16/9;
static bool zoomedToFill = false;
static bool engagementPanelIsVisible = false, removeEngagementPanelViewControllerWithIdentifierCalled = false;

static MLHAMSBDLSampleBufferRenderingView *renderingView;
static NSLayoutConstraint *widthConstraint, *heightConstraint, *centerXConstraint, *centerYConstraint;

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

    // Making renderingView a bit larger since constraining to safe area leaves a gap between the notch and video
    CGFloat constant = 22.0; // Tested on iPhone 13 mini

    widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.widthAnchor constant:constant];
    heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.heightAnchor constant:constant];
    centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:renderingViewContainer.centerXAnchor];
    centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:renderingViewContainer.centerYAnchor];
    
    // playerView.backgroundColor = [UIColor blueColor];
    // renderingViewContainer.backgroundColor = [UIColor greenColor];
    // renderingView.backgroundColor = [UIColor redColor];

    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];

    // Must check class since YTInlineMutedPlaybackPlayerOverlayViewController doesn't have -(BOOL)isFullscreen
    if ([NSStringFromClass([activeVideoPlayerOverlay class]) isEqualToString:@"YTMainAppVideoPlayerOverlayViewController"] // isKindOfClass doesn't work for some reason
    && [activeVideoPlayerOverlay isFullscreen]) {
        if (!zoomedToFill && !engagementPanelIsVisible) DEMC_activate();
    } else {
        DEMC_centerRenderingView();
    }

    %orig(animated);
}
- (void)didPressToggleFullscreen {
    %orig;
    if (![[self activeVideoPlayerOverlay] isFullscreen]) { // Entering full screen
        if (!zoomedToFill && !engagementPanelIsVisible) DEMC_activate();
    } else { // Exiting full screen
        DEMC_deactivate();
    } 
}
- (void)didSwipeToEnterFullscreen { 
    %orig; 
    if (!zoomedToFill && !engagementPanelIsVisible) DEMC_activate();
}
- (void)didSwipeToExitFullscreen { 
    %orig; 
    DEMC_deactivate(); 
}
// New video played
-(void)playbackController:(id)playbackController didActivateVideo:(id)video withPlaybackData:(id)playbackData {
    %orig(playbackController, video, playbackData);
    if ([[self activeVideoPlayerOverlay] isFullscreen]) // New video played while in full screen (landscape)
        // Activate since new videos played in full screen aren't zoomed-to-fill by default
        // (i.e. the notch/Dynamic Island will cut into content when playing a new video in full screen)
        DEMC_activate(); 
    engagementPanelIsVisible = false;
    removeEngagementPanelViewControllerWithIdentifierCalled = false;
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
        zoomedToFill = false;
        DEMC_activate();
    } else if (snapState == 1) { // Zoomed to fill
        zoomedToFill = true;
        // No need to deactivate constraints as it's already done in -(void)didRecognizePinch:(UIPinchGestureRecognizer *)
    }
    %orig(snapState);
}
%end

// Mini bar dismiss
%hook YTWatchMiniBarViewController
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType {
    %orig(velocity, gestureType);
    zoomedToFill = false; // Setting to false since YouTube undoes zoom-to-fill when mini bar is dismissed
}
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType skipShouldDismissCheck:(BOOL)skipShouldDismissCheck {
    %orig(velocity, gestureType, skipShouldDismissCheck);
    zoomedToFill = false;
}
%end

%hook YTMainAppEngagementPanelViewController
// Engagement panel (comment, description, etc.) about to show up
- (void)viewWillAppear:(BOOL)animated {
    if ([self isPeekingSupported]) {
        // Shorts (only Shorts support peeking, I think)
    } else {
        // Everything else
        engagementPanelIsVisible = true;
        if ([self isLandscapeEngagementPanel]) {
            DEMC_deactivate();
        }
    }
    %orig(animated);
}
// Engagement panel about to dismiss
// - (void)viewDidDisappear:(BOOL)animated { %orig; %log; } // Called too late & isn't reliable so sometimes constraints aren't activated even when engagement panel is closed
%end

%hook YTEngagementPanelContainerViewController
// Engagement panel about to dismiss
- (void)notifyEngagementPanelContainerControllerWillHideFinalPanel { // Called in time but crashes if plays new video while in full screen causing engagement panel dismissal
    // Must check if engagement panel was dismissed because new video played
    // (i.e. if -(void)removeEngagementPanelViewControllerWithIdentifier:(id) was called prior)
    if (![self isPeekingSupported] && !removeEngagementPanelViewControllerWithIdentifierCalled) {
        engagementPanelIsVisible = false;
        if ([self isLandscapeEngagementPanel] && !zoomedToFill) {
            DEMC_activate();
        }
    }
    %orig;
}
- (void)removeEngagementPanelViewControllerWithIdentifier:(id)identifier {
    // Usually called when engagement panel is open & new video is played or mini bar is dismissed
    removeEngagementPanelViewControllerWithIdentifierCalled = true;
    %orig(identifier);
}
%end

%end// group DontEatMyContent

%ctor {
    if (DEMC_deviceIsSupported()) %init(DontEatMyContent);
}

static BOOL DEMC_deviceIsSupported() {
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
    DEMC_centerRenderingView();
    renderingView.translatesAutoresizingMaskIntoConstraints = YES;
    widthConstraint.active = NO;
    heightConstraint.active = NO;
}

static void DEMC_centerRenderingView() {
    centerXConstraint.active = YES;
    centerYConstraint.active = YES;
}
