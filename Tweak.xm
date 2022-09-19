#import <sys/utsname.h>
// #import <substrate.h>
#import "Tweak.h"

const double THRESHOLD = 1.99;
double aspectRatio = 16/9;

MLHAMSBDLSampleBufferRenderingView *renderingView;
NSLayoutConstraint *widthConstraint, *heightConstraint, *centerXConstraint, *centerYConstraint;

%group DontEatMyContent

// %hook YTMainAppVideoPlayerOverlayViewController
// - (void)viewDidAppear:(BOOL)animated { %orig; }
// - (void)maybeInitVideoZoom { %log; %orig;}
// - (void)videoZoomBegan { %log; %orig;}
// - (void)videoZoomEnded { %log; %orig; }
// %end

// %hook YTMainAppVideoPlayerOverlayView
// - (BOOL)iPhoneXShouldForceLandscapeFullscreenSafeArea {
//     %log; return YES;
// }
// %end

%hook YTPlayerViewController

- (void)didPressToggleFullscreen { 
    %orig;
    
    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];
    // Entering fullscreen
    if (![activeVideoPlayerOverlay isFullscreen]) activate();
    // Exiting fullscreen
    else deactivate();
}

- (void)didSwipeToEnterFullscreen { 
    %log; 
    %orig; activate();
}

- (void)didSwipeToExitFullscreen { 
    %log; 
    %orig; deactivate();
}

- (void)viewDidAppear:(BOOL)animated {
    // YTPlayerView *playerView = MSHookIvar<YTPlayerView *>(self, "_view");
	// renderingView = MSHookIvar<MLHAMSBDLSampleBufferRenderingView *>(playerView, "_renderingView");
    YTPlayerView *playerView = [self playerView];
	renderingView = [playerView renderingView];

    YTMainAppVideoPlayerOverlayViewController *activeVideoPlayerOverlay = [self activeVideoPlayerOverlay];
    // YTMainAppVideoPlayerOverlayView *videoPlayerOverlayView = [activeVideoPlayerOverlay videoPlayerOverlayView];

    CGFloat constant = 23; // Make renderingView a bit larger since safe area has sizeable margins from the notch and side borders; tested on iPhone 13 mini

    widthConstraint = [renderingView.widthAnchor constraintEqualToAnchor:playerView.safeAreaLayoutGuide.widthAnchor constant:constant];
    heightConstraint = [renderingView.heightAnchor constraintEqualToAnchor:playerView.safeAreaLayoutGuide.heightAnchor constant:constant];
    centerXConstraint = [renderingView.centerXAnchor constraintEqualToAnchor:playerView.centerXAnchor];
    centerYConstraint = [renderingView.centerYAnchor constraintEqualToAnchor:playerView.centerYAnchor];
    
    // playerView.backgroundColor = [UIColor greenColor];
    // renderingView.backgroundColor = [UIColor blueColor];

    if (animated && [activeVideoPlayerOverlay isFullscreen]) {
        %log(@"fullscreen");
        activate();
    } else {
        %log(@"not fullscreen");
        // deactivate();
        center();
    }

    %orig(animated);
}

// - (void)viewDidLoad { %log; %orig; } // Playback in feeds
// - (void)updateActiveOverlayWithActiveVideoCurrentState { %log; %orig; }
// - (void)updateUIStateWithActiveVideoCurrentState { %log; %orig; }
// - (void)startObservingStateChangesOnActiveVideo { %log; %orig; }

- (void)singleVideo:(id)arg1 aspectRatioDidChange:(CGFloat)arg2 {
    %log((id) arg1, (CGFloat) arg2);

    aspectRatio = arg2;
    %log((CGFloat) aspectRatio);
    
    if (aspectRatio < THRESHOLD) {
        deactivate();
    } else activate();

    %orig(arg1, arg2);
}

%end

%hook YTVideoZoomOverlayView

- (void)didRecognizePinch:(UIPinchGestureRecognizer *)pinchGestureRecognizer {
    // %log((CGFloat) [pinchGestureRecognizer scale], (CGFloat) [pinchGestureRecognizer velocity]);
    if ([pinchGestureRecognizer velocity] <= 0.0) { // >>Zoom out<<
        activate();
    } else if ([pinchGestureRecognizer velocity] > 0.0) { // <<Zoom in>>
        deactivate();
    }

    %orig(pinchGestureRecognizer);
}

- (void)flashAndHideSnapIndicator {}

// https://github.com/lgariv/UniZoom/blob/master/Tweak.xm
- (void)setSnapIndicatorVisible:(bool)arg1 {
    %orig(NO);
}

%end

%end // group DontEatMyContent

%ctor {
    if (deviceIsSupported()) %init(DontEatMyContent);
}

// https://stackoverflow.com/a/11197770/19227228
NSString* deviceName() {
    struct utsname systemInfo;
    uname(&systemInfo);
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

BOOL deviceIsSupported() {
    NSString *identifier = deviceName();
    if ([identifier containsString:@"iPhone"]) {
        NSString *model = [identifier stringByReplacingOccurrencesOfString:@"iPhone" withString:@""];
        if ([model isEqualToString:@"13,1"]) // iPhone 12 mini
            return YES; 
        else if ([model floatValue] >= 14.0) // iPhone 13 series and newer
            return YES;
        else return NO;
    } else return NO;
}

void activate() {
    if (aspectRatio < THRESHOLD) return;
    NSLog(@"activate");
    center();
    renderingView.translatesAutoresizingMaskIntoConstraints = NO;
    widthConstraint.active = YES;
    heightConstraint.active = YES;
}

void deactivate() {
    NSLog(@"deactivate");
    center();
    renderingView.translatesAutoresizingMaskIntoConstraints = YES;
    widthConstraint.active = NO;
    heightConstraint.active = NO;
}

void center() {
    centerXConstraint.active = YES;
    centerYConstraint.active = YES;
}
