TARGET := iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DontEatMyContent

DontEatMyContent_FILES = Tweak.xm
DontEatMyContent_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
