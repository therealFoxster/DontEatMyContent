#include "DuoCutout.h"

static const double kClearance = 0.05;

static int demc_empty(DEMCRect rect) {
    return !(rect.width > 0.0) || !(rect.height > 0.0);
}

static double demc_abs(double value) {
    return value < 0.0 ? -value : value;
}

DEMCRect DEMCRectMake(double x, double y, double width, double height) {
    DEMCRect rect;
    rect.x = x;
    rect.y = y;
    rect.width = width;
    rect.height = height;
    return rect;
}

DEMCRect DEMCRectOutset(DEMCRect rect, double pad) {
    return DEMCRectMake(rect.x - pad, rect.y - pad, rect.width + pad * 2.0, rect.height + pad * 2.0);
}

int DEMCRectIntersects(DEMCRect a, DEMCRect b) {
    if (demc_empty(a) || demc_empty(b))
        return 0;
    return a.x < b.x + b.width &&
           b.x < a.x + a.width &&
           a.y < b.y + b.height &&
           b.y < a.y + a.height;
}

static int DEMCRectContains(DEMCRect outer, DEMCRect inner) {
    if (demc_empty(inner) || demc_empty(outer))
        return 0;
    return inner.x >= outer.x - 1e-4 &&
           inner.y >= outer.y - 1e-4 &&
           inner.x + inner.width <= outer.x + outer.width + 1e-4 &&
           inner.y + inner.height <= outer.y + outer.height + 1e-4;
}

int DEMCSizeIsDuoOuterDisplay(double width, double height) {
    double shorter = width < height ? width : height;
    double longer = width < height ? height : width;
    return demc_abs(shorter - 466.0) <= 2.0 && demc_abs(longer - 678.0) <= 2.0;
}

int DEMCPixelsAreDuoOuterDisplay(double width, double height) {
    double shorter = width < height ? width : height;
    double longer = width < height ? height : width;
    return demc_abs(shorter - 1398.0) <= 2.0 && demc_abs(longer - 2034.0) <= 2.0;
}

DEMCRect DEMCScalePortraitLens(double portraitWidth, double portraitHeight) {
    DEMCRect lens = DEMCDuoOuterLensPortraitRect();
    if (!(portraitWidth > 0.0) || !(portraitHeight > 0.0))
        return lens;
    double sx = portraitWidth / 466.0;
    double sy = portraitHeight / 678.0;
    lens.x *= sx;
    lens.y *= sy;
    lens.width *= sx;
    lens.height *= sy;
    return lens;
}

DEMCRect DEMCDuoOuterLensPortraitRect(void) {
    const double diameter = 37.0;
    const double centerX = 417.8;
    const double centerY = 47.8;
    return DEMCRectMake(centerX - diameter * 0.5, centerY - diameter * 0.5, diameter, diameter);
}

static DEMCRect demc_fit(DEMCRect region, double aspect) {
    DEMCRect empty = DEMCRectMake(0, 0, 0, 0);
    if (demc_empty(region) || !(aspect > 0.0))
        return empty;
    double width = region.height * aspect;
    double height = region.height;
    if (width > region.width) {
        width = region.width;
        height = region.width / aspect;
    }
    if (!(width > 0.0) || !(height > 0.0))
        return empty;
    return DEMCRectMake(region.x + (region.width - width) * 0.5,
                         region.y + (region.height - height) * 0.5,
                         width,
                         height);
}

DEMCRect DEMCCenteredVideoRect(DEMCRect container, double aspect) {
    return demc_fit(container, aspect);
}

typedef struct {
    double lo;
    double hi;
    int ok;
} DemcInterval;

static DemcInterval demc_overlap(double a0, double a1, double b0, double b1) {
    DemcInterval interval;
    interval.lo = a0 > b0 ? a0 : b0;
    interval.hi = a1 < b1 ? a1 : b1;
    interval.ok = interval.lo <= interval.hi + 1e-7;
    return interval;
}

static double demc_clamp(double value, double lo, double hi) {
    if (value < lo)
        return lo;
    if (value > hi)
        return hi;
    return value;
}

static DEMCRect demc_slide(DEMCRect container, double width, double height, DEMCRect cutout) {
    DEMCRect empty = DEMCRectMake(0, 0, 0, 0);
    double minX = container.x;
    double maxX = container.x + container.width - width;
    double minY = container.y;
    double maxY = container.y + container.height - height;
    if (maxX < minX - 1e-4 || maxY < minY - 1e-4)
        return empty;
    if (maxX < minX)
        maxX = minX;
    if (maxY < minY)
        maxY = minY;

    double centerX = (minX + maxX) * 0.5;
    double centerY = (minY + maxY) * 0.5;
    DemcInterval optionsX[4];
    DemcInterval optionsY[4];
    optionsX[0] = demc_overlap(minX, maxX, -1e300, cutout.x - width - kClearance);
    optionsY[0] = demc_overlap(minY, maxY, -1e300, 1e300);
    optionsX[1] = demc_overlap(minX, maxX, cutout.x + cutout.width + kClearance, 1e300);
    optionsY[1] = demc_overlap(minY, maxY, -1e300, 1e300);
    optionsX[2] = demc_overlap(minX, maxX, -1e300, 1e300);
    optionsY[2] = demc_overlap(minY, maxY, -1e300, cutout.y - height - kClearance);
    optionsX[3] = demc_overlap(minX, maxX, -1e300, 1e300);
    optionsY[3] = demc_overlap(minY, maxY, cutout.y + cutout.height + kClearance, 1e300);

    int found = 0;
    double bestDistance = 0;
    DEMCRect best = empty;
    for (int i = 0; i < 4; i++) {
        if (!optionsX[i].ok || !optionsY[i].ok)
            continue;
        double x = demc_clamp(centerX, optionsX[i].lo, optionsX[i].hi);
        double y = demc_clamp(centerY, optionsY[i].lo, optionsY[i].hi);
        double dx = x - centerX;
        double dy = y - centerY;
        double distance = dx * dx + dy * dy;
        if (!found || distance < bestDistance) {
            found = 1;
            bestDistance = distance;
            best = DEMCRectMake(x, y, width, height);
        }
    }
    return found ? best : empty;
}

static DEMCRect demc_clamp_slab(DEMCRect slab, DEMCRect container) {
    if (slab.x < container.x) {
        slab.width -= container.x - slab.x;
        slab.x = container.x;
    }
    if (slab.y < container.y) {
        slab.height -= container.y - slab.y;
        slab.y = container.y;
    }
    double right = container.x + container.width;
    double bottom = container.y + container.height;
    if (slab.x + slab.width > right)
        slab.width = right - slab.x;
    if (slab.y + slab.height > bottom)
        slab.height = bottom - slab.y;
    return slab;
}

DEMCRect DEMCVideoRectAvoidingCutout(DEMCRect container, DEMCRect cutout, double aspect) {
    DEMCRect empty = DEMCRectMake(0, 0, 0, 0);
    DEMCRect centered = demc_fit(container, aspect);
    if (demc_empty(centered))
        return empty;
    if (demc_empty(cutout) || !DEMCRectIntersects(cutout, container) || !DEMCRectIntersects(centered, cutout))
        return centered;

    DEMCRect slid = demc_slide(container, centered.width, centered.height, cutout);
    if (!demc_empty(slid) && !DEMCRectIntersects(slid, cutout) && DEMCRectContains(container, slid))
        return slid;

    DEMCRect slabs[4];
    slabs[0] = DEMCRectMake(container.x, container.y, cutout.x - container.x - kClearance, container.height);
    slabs[1] = DEMCRectMake(cutout.x + cutout.width + kClearance, container.y,
                             (container.x + container.width) - (cutout.x + cutout.width) - kClearance, container.height);
    slabs[2] = DEMCRectMake(container.x, container.y, container.width, cutout.y - container.y - kClearance);
    slabs[3] = DEMCRectMake(container.x, cutout.y + cutout.height + kClearance, container.width,
                             (container.y + container.height) - (cutout.y + cutout.height) - kClearance);

    DEMCRect best = empty;
    double bestArea = 0;
    double bestDistance = 0;
    int have = 0;
    double midX = container.x + container.width * 0.5;
    double midY = container.y + container.height * 0.5;
    for (int i = 0; i < 4; i++) {
        DEMCRect slab = demc_clamp_slab(slabs[i], container);
        if (demc_empty(slab))
            continue;
        DEMCRect fit = demc_fit(slab, aspect);
        if (demc_empty(fit) || DEMCRectIntersects(fit, cutout) || !DEMCRectContains(container, fit))
            continue;
        double area = fit.width * fit.height;
        double dx = (fit.x + fit.width * 0.5) - midX;
        double dy = (fit.y + fit.height * 0.5) - midY;
        double distance = dx * dx + dy * dy;
        if (!have || area > bestArea + 0.5 || (demc_abs(area - bestArea) <= 0.5 && distance < bestDistance)) {
            have = 1;
            bestArea = area;
            bestDistance = distance;
            best = fit;
        }
    }
    return best;
}

static int demc_spans(DEMCRect rect, DEMCRect container) {
    if (!(container.width > 0.0) || !(container.height > 0.0))
        return 1;
    return rect.width >= container.width * 0.9 || rect.height >= container.height * 0.9;
}

DEMCRect DEMCChooseCutout(const DEMCRect *rects, int count, DEMCRect container) {
    DEMCRect empty = DEMCRectMake(0, 0, 0, 0);
    DEMCRect kept[8];
    int keptCount = 0;
    if (!rects || count <= 0)
        return empty;
    for (int i = 0; i < count && keptCount < 8; i++) {
        if (demc_empty(rects[i]) || demc_spans(rects[i], container))
            continue;
        kept[keptCount++] = rects[i];
    }
    if (keptCount == 0)
        return empty;
    if (keptCount == 1)
        return kept[0];

    DEMCRect unionRect = kept[0];
    for (int i = 1; i < keptCount; i++) {
        double x0 = unionRect.x < kept[i].x ? unionRect.x : kept[i].x;
        double y0 = unionRect.y < kept[i].y ? unionRect.y : kept[i].y;
        double x1 = (unionRect.x + unionRect.width) > (kept[i].x + kept[i].width)
            ? (unionRect.x + unionRect.width) : (kept[i].x + kept[i].width);
        double y1 = (unionRect.y + unionRect.height) > (kept[i].y + kept[i].height)
            ? (unionRect.y + unionRect.height) : (kept[i].y + kept[i].height);
        unionRect = DEMCRectMake(x0, y0, x1 - x0, y1 - y0);
    }
    // Regions scattered across the screen are not the corner camera. The caller
    // falls back to the measured lens instead of dodging the bounding box.
    if (demc_spans(unionRect, container))
        return empty;
    return unionRect;
}

#ifdef DEMC_CUTOUT_MAIN
#include <stdio.h>

static int failures = 0;

#define expect(cond) do { \
    if (!(cond)) { \
        fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); \
        failures++; \
    } \
} while (0)

static DEMCRect transform_lens(int rotation, double *outWidth, double *outHeight) {
    DEMCRect lens = DEMCDuoOuterLensPortraitRect();
    const double portraitW = 466.0;
    const double portraitH = 678.0;
    double xs[4] = { lens.x, lens.x + lens.width, lens.x, lens.x + lens.width };
    double ys[4] = { lens.y, lens.y, lens.y + lens.height, lens.y + lens.height };
    double minX = 1e300, minY = 1e300, maxX = -1e300, maxY = -1e300;
    for (int i = 0; i < 4; i++) {
        double x, y;
        if (rotation == 0) {
            x = xs[i];
            y = ys[i];
            *outWidth = portraitW;
            *outHeight = portraitH;
        } else if (rotation == 1) {
            x = portraitH - ys[i];
            y = xs[i];
            *outWidth = portraitH;
            *outHeight = portraitW;
        } else if (rotation == 2) {
            x = ys[i];
            y = portraitW - xs[i];
            *outWidth = portraitH;
            *outHeight = portraitW;
        } else {
            x = portraitW - xs[i];
            y = portraitH - ys[i];
            *outWidth = portraitW;
            *outHeight = portraitH;
        }
        if (x < minX) minX = x;
        if (y < minY) minY = y;
        if (x > maxX) maxX = x;
        if (y > maxY) maxY = y;
    }
    return DEMCRectMake(minX, minY, maxX - minX, maxY - minY);
}

static double separation(DEMCRect a, DEMCRect b) {
    double dx = 0;
    if (a.x + a.width <= b.x)
        dx = b.x - (a.x + a.width);
    else if (b.x + b.width <= a.x)
        dx = a.x - (b.x + b.width);
    double dy = 0;
    if (a.y + a.height <= b.y)
        dy = b.y - (a.y + a.height);
    else if (b.y + b.height <= a.y)
        dy = a.y - (b.y + b.height);
    if (dx > 0 && dy > 0) {
        double hyp = dx * dx + dy * dy;
        double guess = dx > dy ? dx : dy;
        for (int i = 0; i < 6; i++)
            guess = 0.5 * (guess + hyp / guess);
        return guess;
    }
    return dx > dy ? dx : dy;
}

int main(void) {
    expect(DEMCSizeIsDuoOuterDisplay(466, 678));
    expect(DEMCSizeIsDuoOuterDisplay(678, 466));
    expect(DEMCSizeIsDuoOuterDisplay(467, 677));
    expect(!DEMCSizeIsDuoOuterDisplay(393, 852));
    expect(!DEMCSizeIsDuoOuterDisplay(626, 890));
    expect(!DEMCSizeIsDuoOuterDisplay(440, 956));
    expect(DEMCPixelsAreDuoOuterDisplay(1398, 2034));
    expect(DEMCPixelsAreDuoOuterDisplay(2034, 1398));
    expect(!DEMCPixelsAreDuoOuterDisplay(1179, 2556));
    expect(!DEMCPixelsAreDuoOuterDisplay(1878, 2670));
    DEMCRect scaled = DEMCScalePortraitLens(466, 678);
    DEMCRect standard = DEMCDuoOuterLensPortraitRect();
    expect(demc_abs(scaled.x - standard.x) < 0.01);
    expect(demc_abs(scaled.width - standard.width) < 0.01);
    scaled = DEMCScalePortraitLens(466 * 0.8, 678 * 0.8);
    expect(demc_abs(scaled.width - standard.width * 0.8) < 0.05);

    const double aspects[] = { 16.0 / 9.0, 2.0, 2.39, 9.0 / 16.0 };
    for (int rotation = 0; rotation < 4; rotation++) {
        double width = 0, height = 0;
        DEMCRect lens = transform_lens(rotation, &width, &height);
        DEMCRect container = DEMCRectMake(0, 0, width, height);
        expect(DEMCRectContains(container, lens));
        for (int a = 0; a < 4; a++) {
            DEMCRect video = DEMCVideoRectAvoidingCutout(container, lens, aspects[a]);
            expect(!demc_empty(video));
            expect(DEMCRectContains(container, video));
            expect(!DEMCRectIntersects(video, lens));
        }
        DEMCRect full = DEMCVideoRectAvoidingCutout(container, lens, width / height);
        expect(DEMCRectContains(container, full));
        expect(!DEMCRectIntersects(full, lens));
        expect(full.width * full.height > width * height * 0.75);

        DEMCRect padded = DEMCRectOutset(lens, 2.0);
        DEMCRect cleared = DEMCVideoRectAvoidingCutout(container, padded, 16.0 / 9.0);
        expect(!DEMCRectIntersects(cleared, padded));
        expect(separation(cleared, lens) >= 1.9);
    }

    double landscapeW = 0, landscapeH = 0;
    DEMCRect landscapeLens = transform_lens(2, &landscapeW, &landscapeH);
    DEMCRect landscape = DEMCRectMake(0, 0, landscapeW, landscapeH);
    DEMCRect wide = DEMCVideoRectAvoidingCutout(landscape, landscapeLens, 16.0 / 9.0);
    DEMCRect wideCentered = DEMCCenteredVideoRect(landscape, 16.0 / 9.0);
    expect(demc_abs(wide.width - wideCentered.width) < 0.2);
    expect(demc_abs(wide.height - wideCentered.height) < 0.2);
    expect(wide.y > wideCentered.y);
    expect(DEMCRectIntersects(wideCentered, landscapeLens));

    DEMCRect portrait = DEMCRectMake(0, 0, 466, 678);
    DEMCRect lens = DEMCDuoOuterLensPortraitRect();
    DEMCRect portraitWide = DEMCVideoRectAvoidingCutout(portrait, lens, 16.0 / 9.0);
    DEMCRect portraitCentered = DEMCCenteredVideoRect(portrait, 16.0 / 9.0);
    expect(demc_abs(portraitWide.x - portraitCentered.x) < 0.2);
    expect(demc_abs(portraitWide.y - portraitCentered.y) < 0.2);
    expect(!DEMCRectIntersects(portraitCentered, lens));

    DEMCRect portraitTall = DEMCVideoRectAvoidingCutout(portrait, lens, 9.0 / 16.0);
    DEMCRect tallCentered = DEMCCenteredVideoRect(portrait, 9.0 / 16.0);
    expect(DEMCRectIntersects(tallCentered, lens));
    expect(demc_abs(portraitTall.width - tallCentered.width) < 0.2);
    expect(portraitTall.x + portraitTall.width <= lens.x);

    // The old safe-area constraints center a one-sided inset, so the
    // rendering view still covers the corner lens.
    DEMCRect oldCentered = DEMCRectMake((466.0 - (382.0 + 21.5)) * 0.5, 0, 382.0 + 21.5, 678);
    expect(DEMCRectIntersects(oldCentered, lens));
    DEMCRect replaced = DEMCVideoRectAvoidingCutout(portrait, lens, 466.0 / 678.0);
    expect(!DEMCRectIntersects(replaced, lens));

    DEMCRect outside = DEMCRectMake(1000, 1000, 10, 10);
    DEMCRect untouched = DEMCVideoRectAvoidingCutout(portrait, outside, 16.0 / 9.0);
    expect(demc_abs(untouched.x - portraitCentered.x) < 0.01);

    DEMCRect none = DEMCVideoRectAvoidingCutout(portrait, DEMCRectMake(0, 0, 0, 0), 16.0 / 9.0);
    expect(demc_abs(none.y - portraitCentered.y) < 0.01);
    expect(demc_empty(DEMCVideoRectAvoidingCutout(portrait, lens, 0)));

    DEMCRect centerHole = DEMCRectMake(319, 213, 40, 40);
    DEMCRect aroundHole = DEMCVideoRectAvoidingCutout(landscape, centerHole, 16.0 / 9.0);
    expect(!DEMCRectIntersects(aroundHole, centerHole));
    expect(DEMCRectContains(landscape, aroundHole));

    DEMCRect regions[3];
    regions[0] = DEMCRectMake(0, 300, 466, 20);
    regions[1] = lens;
    DEMCRect chosen = DEMCChooseCutout(regions, 2, portrait);
    expect(demc_abs(chosen.x - lens.x) < 0.01);
    expect(demc_abs(chosen.y - lens.y) < 0.01);

    regions[0] = lens;
    regions[1] = DEMCRectOutset(lens, 4);
    chosen = DEMCChooseCutout(regions, 2, portrait);
    expect(DEMCRectContains(chosen, lens));
    expect(chosen.width > lens.width);

    regions[0] = lens;
    regions[1] = DEMCRectMake(8, 600, 30, 30);
    expect(demc_empty(DEMCChooseCutout(regions, 2, portrait)));

    expect(demc_empty(DEMCChooseCutout(NULL, 0, portrait)));
    regions[0] = DEMCRectMake(0, 0, 466, 8);
    expect(demc_empty(DEMCChooseCutout(regions, 1, portrait)));

    if (failures) {
        fprintf(stderr, "%d failure(s)\n", failures);
        return 1;
    }
    printf("duo cutout layout ok\n");
    return 0;
}
#endif
