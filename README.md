# DontEatMyContent
Prevent the notch/Dynamic Island from munching on 2:1 video content in YouTube

## How It Works

The rendering view is constrained to the safe area layout guide and center of its container, meaning it will always be below the notch and, presumably, Dynamic Island. This behaviour is only activated when viewing videos with 2:1 aspect ratio or wider (untested) to prevent unintended side effects on smaller aspect ratios. 

## Compatibility
Works on iPhone 12 mini, iPhone 13 series and newer except iPhone SE 3rd generation, iPhone 13 Pro Max and iPhone 14 Plus.

## Screenshots
### iPhone 13 mini

![original](../assets/screenshots/IMG_2096.PNG)

**Figure 1.** Original implementation

![tweaked](../assets/screenshots/IMG_2097.PNG)

**Figure 2.** Tweaked implementation

![zoom to fill](../assets/screenshots/IMG_2098.PNG)

**Figure 3.** Zoomed to fill
