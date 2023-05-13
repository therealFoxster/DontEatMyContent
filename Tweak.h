#import <UIKit/UIKit.h>

@interface YTPlayerViewController : UIViewController
- (id)activeVideoPlayerOverlay;
- (id)playerView;
- (BOOL)isCurrentVideoVertical;
@end

@interface YTPlayerView : UIView
- (id)renderingView;
@end

@interface YTMainAppVideoPlayerOverlayViewController : UIViewController
- (BOOL)isFullscreen;
@end

@interface HAMSBDLSampleBufferRenderingView : UIView
@end

@interface MLHAMSBDLSampleBufferRenderingView : HAMSBDLSampleBufferRenderingView
@end

@interface YTMainAppEngagementPanelViewController : UIViewController
- (BOOL)isLandscapeEngagementPanel;
- (BOOL)isPeekingSupported;
@end

@interface YTEngagementPanelContainerViewController : UIViewController
- (BOOL)isLandscapeEngagementPanel;
- (BOOL)isPeekingSupported;
@end

static BOOL DEMC_isDeviceSupported();
static void DEMC_activate();
static void DEMC_deactivate(); 
static void DEMC_centerRenderingView();
