export THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard
DEBUG = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCNine
CCNine_FILES = Tweak.x CC9Backend.m CC9Controls.m CC9ViewController.m
CCNine_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
CCNine_FRAMEWORKS = UIKit AVFoundation AVKit
# Tout le privé est chargé via dlopen/objc_getClass : aucun lien privé => pas de crash au chargement

include $(THEOS_MAKE_PATH)/tweak.mk
