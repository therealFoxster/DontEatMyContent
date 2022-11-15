# DontEatMyContent
Prevent the notch/Dynamic Island from munching on 2:1 video content in YouTube

## How It Works
The rendering view is constrained to the safe area layout guide of its container, meaning it will always be below the notch and, presumably, Dynamic Island. These constraints are only activated when viewing videos with 2:1 aspect ratio (or wider; untested) to prevent unintended side effects on videos with smaller aspect ratios. 

## Compatibility
Supports iPhone 12 mini, iPhone 13 series and newer **except** iPhone SE 3rd generation, iPhone 13 Pro Max and iPhone 14 Plus.

> **Note**: From [v1.0.4](https://github.com/therealFoxster/DontEatMyContent/releases/tag/v1.0.4) onwards, the tweak only supports YouTube versions that got the [October 2022 redesign](https://blog.youtube/news-and-events/an-updated-look-and-feel-for-youtube/). v1.0.4 was tested and confirmed to be working with YouTube v17.43.1.

## Grab It
- .ipa file (tweak-injected YouTube app): https://therealfoxster.github.io/altsource/app.html?id=youtube
- .deb file: https://github.com/therealFoxster/DontEatMyContent/releases/latest

## Screenshots (iPhone 13 mini)

### Original Implementation
![original](../assets/readme/original.PNG)

### Tweaked Implementation
![tweaked](../assets/readme/tweaked.PNG)

### Zoomed to Fill
![zoom to fill](../assets/readme/zoomed_to_fill.PNG)

## License
[The MIT License](LICENSE.md)
