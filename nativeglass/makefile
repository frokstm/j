THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64e
TARGET = iphone:clang:latest:18.0

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ControlCenter26
ControlCenter26_FILES = NativeGlass.m
ControlCenter26_CFLAGS = -fobjc-arc
ControlCenter26_FRAMEWORKS = UIKit QuartzCore
ControlCenter26_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "sbreload"

