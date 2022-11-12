#import <sys/utsname.h>
#import <substrate.h>
#import "Tweak.h"

#define UNSUPPORTED_DEVICES @[@"iPhone14,3", @"iPhone14,6", @"iPhone14,8"]
#define THRESHOLD 1.99

static double videoAspectRatio = 16/9;
static bool isZoomedToFill = false, isFullscreen = false, isNewVideo = true;

static MLHAMSBDLSampleBufferRenderingView *renderingView;
static NSLayoutConstraint *widthConstraint, *heightConstraint, *centerXConstraint, *centerYConstraint;

%group DontEatMyContentHooks

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

    CGFloat constant = 23; // Make renderingView a bit larger since safe area has sizeable margins from the notch and side borders; tested on iPhone 13 mini

    widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.widthAnchor constant:constant];
    heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:renderingViewContainer.safeAreaLayoutGuide.heightAnchor constant:constant];
    centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:renderingViewContainer.centerXAnchor];
    centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:renderingViewContainer.centerYAnchor];
    
    // playerView.backgroundColor = [UIColor greenColor];
    // renderingViewContainer.backgroundColor = [UIColor redColor];
    // renderingView.backgroundColor = [UIColor blueColor];

    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];

    // Must check class since YTInlineMutedPlaybackPlayerOverlayViewController doesn't have -(BOOL)isFullscreen
    if ([NSStringFromClass([activeVideoPlayerOverlay class]) isEqualToString:@"YTMainAppVideoPlayerOverlayViewController"] 
    && [activeVideoPlayerOverlay isFullscreen]) {
        if (!isZoomedToFill) DEMC_activate();
        isFullscreen = true;
    } else {
        DEMC_centerRenderingView();
        isFullscreen = false;
    }

    %orig(animated);
}
- (void)didPressToggleFullscreen {
    %orig;
    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];
    if (![activeVideoPlayerOverlay isFullscreen]) { // Entering full screen
        if (!isZoomedToFill) DEMC_activate();
    } else { // Exiting full screen
        DEMC_deactivate();
    } 
}
- (void)didSwipeToEnterFullscreen { 
    %orig; 
    if (!isZoomedToFill) DEMC_activate();
}
- (void)didSwipeToExitFullscreen { 
    %orig; 
    DEMC_deactivate(); 
}
%end

%hook MLHAMSBDLSampleBufferRenderingView
- (void)setVideo:(id)video playerConfig:(id)playerConfig {
    %orig(video, playerConfig);
    isNewVideo = true;
}
%end

%hook YTVideoFreeZoomOverlayView
- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    // Pinched to zoom in/out
    DEMC_deactivate();
    %orig(pinchGestureRecognizer);
}
// Detect zoom to fill
- (void)showLabelForSnapState:(NSInteger)snapState {
    if (snapState == 0) { // Original
        isZoomedToFill = false;
        DEMC_activate();
    } else if (snapState == 1) { // Zoomed to fill
        isZoomedToFill = true;
        // No need to deactivate constraints as it's already done in -(void)didRecognizePinch:(UIPinchGestureRecognizer *)
    }
    %orig(snapState);
}
- (void)setEnabled:(BOOL)enabled {
    %orig(enabled);
    if (enabled && isNewVideo && isFullscreen) { // New video played while in full screen (landscape)
        DEMC_activate(); // Activate since new videos played in full screen aren't zoomed-to-fill for first play (i.e. the notch/Dynamic Island will cut into content when playing a new video in full screen)
        isNewVideo = false;
    }
}
%end

%hook YTWatchMiniBarViewController
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType {
    %orig(velocity, gestureType);
    isZoomedToFill = false; // Setting to false since YouTube undoes zoom-to-fill when mini bar is dismissed
}
- (void)dismissMiniBarWithVelocity:(CGFloat)velocity gestureType:(int)gestureType skipShouldDismissCheck:(BOOL)skipShouldDismissCheck {
    %orig(velocity, gestureType, skipShouldDismissCheck);
    isZoomedToFill = false;
}
%end

%end// DontEatMyContentHooks

%ctor {
    if (DEMC_deviceIsSupported()) %init(DontEatMyContentHooks);
}

// https://stackoverflow.com/a/11197770/19227228
static NSString* DEMC_getDeviceModelIdentifier() {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

static BOOL DEMC_deviceIsSupported() {
    NSString *identifier = DEMC_getDeviceModelIdentifier();
    NSArray *unsupportedDevices = UNSUPPORTED_DEVICES;
    
    for (NSString *device in unsupportedDevices) {
        if ([device isEqualToString:identifier]) {
            return NO;
        }
    }

    if ([identifier containsString:@"iPhone"]) {
        NSString *model = [identifier stringByReplacingOccurrencesOfString:@"iPhone" withString:@""];
        model = [model stringByReplacingOccurrencesOfString:@"," withString:@"."];
        if ([identifier isEqualToString:@"iPhone13,1"]) { // iPhone 12 mini
            return YES; 
        } else if ([model floatValue] >= 14.0) { // iPhone 13 series and newer
            return YES;
        } else return NO;
    } else return NO;
}

static void DEMC_activate() {
    if (videoAspectRatio < THRESHOLD) DEMC_deactivate();
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
