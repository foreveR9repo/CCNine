TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ccninepref
ccninepref_FILES = CC9RootListController.m
ccninepref_FRAMEWORKS = UIKit
# Preferences est un framework privé absent du SDK de la CI : pas de lien, résolution au chargement (Réglages l'a déjà en mémoire)
ccninepref_LDFLAGS = -undefined dynamic_lookup
ccninepref_INSTALL_PATH = /Library/PreferenceBundles
ccninepref_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
