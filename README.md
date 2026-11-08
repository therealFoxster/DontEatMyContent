# DontEatMyContent

A YouTube tweak that keeps the picture out from under the notch, the Dynamic Island, and the camera cutout on the iPhone Duo’s outer screen.

On other iPhones the rendering view is pinned to the safe area for videos about 2:1 or wider, then nudged outward by the safe-area constant so the frame meets the island instead of leaving a gap. That is unchanged.

The Duo’s outer display is different. It is a 466 × 678 pt panel with a 37 pt camera circle in the top-trailing corner, not a centered island. The safe area is a one-sided rail, so centering a safe-area-sized view puts the picture back on top of that circle. Fullscreen 16:9 is also wider than this short screen, so a normal video runs edge to edge and the lens covers a corner. This build places the largest aspect-fit frame that stays outside the cutout. It slides the picture when letterboxing leaves room, and only shrinks it when the frame would otherwise fill the corner. Zoom to fill still lets the video run under the lens, same as under the notch.

The cutout comes from UIKit’s occlusion reserved region when that API is present, so a Live Activity island is avoided too. Otherwise the layout uses the measured lens: a 37 pt circle centered 47.8 pt from the top and trailing edges of the portrait outer display. The safe-area constant is not applied there.

## Build

[Theos](https://theos.dev/) is required. The YouTube headers this tweak compiles against are included from [therealFoxster/YTHeaders](https://github.com/therealFoxster/YTHeaders) (`655ad036`).

```sh
export THEOS=~/theos
make package FINALPACKAGE=1
```

The package is `me.foxster.donteatmycontent` and it injects into `com.google.ios.youtube`. Rootless packaging matches upstream:

```sh
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
```

There is no host app to run. The layout math for the outer-screen camera can be checked on its own:

```sh
clang -std=c11 -Wall -Wextra -Werror -DDEMC_CUTOUT_MAIN -x c -o /tmp/demc-cutout DuoCutout.m
/tmp/demc-cutout
```

## Settings

YouTube → Settings → DontEatMyContent. The safe-area constant still tunes notched phones. On the Duo outer screen the picture sits just outside the camera regardless of that value.

## License

[MIT](LICENSE.md). Based on [therealFoxster/DontEatMyContent](https://github.com/therealFoxster/DontEatMyContent).
