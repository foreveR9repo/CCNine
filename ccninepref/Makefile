TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ccninepref
ccninepref_FILES = CC9RootListController.m
ccninepref_FRAMEWORKS = UIKit
ccninepref_PRIVATE_FRAMEWORKS = Preferences
ccninepref_INSTALL_PATH = /Library/PreferenceBundles
ccninepref_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
