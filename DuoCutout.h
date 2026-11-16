#ifndef DEMC_DUOCUTOUT_H
#define DEMC_DUOCUTOUT_H

typedef struct {
    double x;
    double y;
    double width;
    double height;
} DEMCRect;

DEMCRect DEMCRectMake(double x, double y, double width, double height);
DEMCRect DEMCRectOutset(DEMCRect rect, double pad);
int DEMCRectIntersects(DEMCRect a, DEMCRect b);

// Outer display: 466 x 678 pt, 1398 x 2034 px.
int DEMCSizeIsDuoOuterDisplay(double width, double height);
int DEMCPixelsAreDuoOuterDisplay(double width, double height);

// 37 pt lens centered at (417.8, 47.8) in portrait screen points.
DEMCRect DEMCDuoOuterLensPortraitRect(void);
DEMCRect DEMCScalePortraitLens(double portraitWidth, double portraitHeight);

DEMCRect DEMCCenteredVideoRect(DEMCRect container, double aspect);
DEMCRect DEMCVideoRectAvoidingCutout(DEMCRect container, DEMCRect cutout, double aspect);

// Compact occlusion rects only. Empty when the rects are a fold band or are
// too spread out to be the camera.
DEMCRect DEMCChooseCutout(const DEMCRect *rects, int count, DEMCRect container);

#endif
