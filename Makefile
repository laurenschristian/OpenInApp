APP_NAME := OpenIn
SCHEME := OpenIn
PROJECT := OpenIn.xcodeproj
CONFIG := Release
BUILD_DIR := build
APP_PATH := $(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app
INSTALL_PATH := /Applications/$(APP_NAME).app
RELEASE_DIR := release
VERSION := $(shell defaults read "$$(pwd)/$(BUILD_DIR)/Build/Products/$(CONFIG)/$(APP_NAME).app/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0.0.0")

.PHONY: bootstrap build install uninstall clean release run

bootstrap:
	@./scripts/bootstrap.sh

build: bootstrap
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) \
		-derivedDataPath $(BUILD_DIR) \
		CODE_SIGN_IDENTITY="-" CODE_SIGNING_ALLOWED=YES \
		build

install: build
	@rm -rf $(INSTALL_PATH)
	cp -R $(APP_PATH) $(INSTALL_PATH)
	/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f $(INSTALL_PATH)

uninstall:
	-pkill -x $(APP_NAME)
	rm -rf $(INSTALL_PATH)

clean:
	rm -rf $(BUILD_DIR)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) clean

release: build
	@mkdir -p $(RELEASE_DIR)
	$(eval VERSION := $(shell defaults read "$$(pwd)/$(APP_PATH)/Contents/Info" CFBundleShortVersionString))
	@echo "Building release v$(VERSION)"
	hdiutil create -volname $(APP_NAME) -srcfolder $(APP_PATH) -ov -format UDZO $(RELEASE_DIR)/$(APP_NAME)-v$(VERSION).dmg
	cd $(BUILD_DIR)/Build/Products/$(CONFIG) && zip -r ../../../../$(RELEASE_DIR)/$(APP_NAME)-v$(VERSION).zip $(APP_NAME).app

run: build
	open $(APP_PATH)
