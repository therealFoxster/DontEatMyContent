#import <UIKit/UIKit.h>

@interface YTPlayerViewController : UIViewController
- (id)activeVideoPlayerOverlay;
- (id)playerView;
@end

@interface YTPlayerView : UIView
- (BOOL)zoomToFill;
- (id)renderingView;
@end

@interface MLHAMSBDLSampleBufferRenderingView : UIView
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
- (BOOL)isFullscreen;
- (id)videoPlayerOverlayView;
@end

@interface YTMainAppVideoPlayerOverlayView : UIView
@end

static NSString* DEMC_getDeviceModelIdentifier();
static BOOL DEMC_deviceIsSupported();
static void DEMC_activate();
static void DEMC_deactivate(); 
static void DEMC_centerRenderingView();
