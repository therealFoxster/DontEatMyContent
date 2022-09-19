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

NSString* deviceName();
BOOL deviceIsSupported();
void activate(); 
void deactivate();
void center();
