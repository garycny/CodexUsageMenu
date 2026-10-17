APP_NAME := CodexUsageMenuBar
APP_DISPLAY_NAME := Codex Usage
BUILD_DIR := .build
OBJ_C_MAIN := Sources/main.m
BIN := $(BUILD_DIR)/$(APP_NAME)
APP_BUNDLE := $(BUILD_DIR)/$(APP_DISPLAY_NAME).app
PKG_ROOT := $(BUILD_DIR)/pkg-root
PKG := $(BUILD_DIR)/$(APP_DISPLAY_NAME).pkg
APP_ZIP := $(BUILD_DIR)/$(APP_DISPLAY_NAME).app.zip
PKG_IDENTIFIER := local.codexusage.menubar.pkg
PKG_SCRIPTS := Packaging/pkg-scripts
PKG_COMPONENT_PLIST := Packaging/component.plist
DEVELOPER_ID_APP ?= $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)
DEVELOPER_ID_INSTALLER ?= $(shell security find-identity -v -p basic 2>/dev/null | sed -n 's/.*"\(Developer ID Installer:[^"]*\)".*/\1/p' | head -n 1)
NOTARY_PROFILE ?= codex-usage-notary
MACOS_MIN := 13.0
PKG_VERSION := $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
INSTALL_DIR := $(HOME)/Applications
INSTALLED_APP := $(INSTALL_DIR)/$(APP_DISPLAY_NAME).app
REPO_ROOT := ../..
RELEASE_DIR := $(REPO_ROOT)/dist
HELPER := $(REPO_ROOT)/scripts/codex_usage.py
ICON := Assets/CodexUsageIcon.icns

.PHONY: build app signed-app pkg signed-pkg notarize-pkg release release-signed release-notarized-pkg app-zip signed-app-zip install run run-app signing-info require-developer-id-app require-developer-id-installer clean

signing-info:
	@echo "Developer ID Application: $${DEVELOPER_ID_APP:-$(DEVELOPER_ID_APP)}"
	@echo "Developer ID Installer:   $${DEVELOPER_ID_INSTALLER:-$(DEVELOPER_ID_INSTALLER)}"
	@echo "Notary profile:           $(NOTARY_PROFILE)"

require-developer-id-app:
	@test -n "$(DEVELOPER_ID_APP)" || (echo "No Developer ID Application certificate found. Install one in Keychain or pass DEVELOPER_ID_APP='Developer ID Application: Name (TEAMID)'." && exit 1)

require-developer-id-installer:
	@test -n "$(DEVELOPER_ID_INSTALLER)" || (echo "No Developer ID Installer certificate found. Install one in Keychain or pass DEVELOPER_ID_INSTALLER='Developer ID Installer: Name (TEAMID)'." && exit 1)

build:
	mkdir -p $(BUILD_DIR)
	clang -fobjc-arc -mmacosx-version-min=$(MACOS_MIN) $(OBJ_C_MAIN) -o $(BIN) -framework Cocoa

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources/scripts"
	cp "$(BIN)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "$(HELPER)" "$(APP_BUNDLE)/Contents/Resources/scripts/codex_usage.py"
	cp "$(ICON)" "$(APP_BUNDLE)/Contents/Resources/CodexUsageIcon.icns"
	cp Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	-xattr -cr "$(APP_BUNDLE)"
	-xattr -d com.apple.FinderInfo "$(APP_BUNDLE)" 2>/dev/null
	dot_clean -m "$(APP_BUNDLE)"
	find "$(APP_BUNDLE)" -name "._*" -delete
	find "$(APP_BUNDLE)" -name ".DS_Store" -delete
	-xattr -d com.apple.FinderInfo "$(APP_BUNDLE)" 2>/dev/null
	codesign --force --deep --sign - "$(APP_BUNDLE)"
	-xattr -d com.apple.FinderInfo "$(APP_BUNDLE)" 2>/dev/null
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"

signed-app: require-developer-id-app app
	codesign --force --deep --options runtime --timestamp --sign "$(DEVELOPER_ID_APP)" "$(APP_BUNDLE)"
	xattr -cr "$(APP_BUNDLE)"
	dot_clean -m "$(APP_BUNDLE)"
	-xattr -d 'com.apple.fileprovider.fpfs#P' "$(APP_BUNDLE)" 2>/dev/null
	-xattr -d com.apple.FinderInfo "$(APP_BUNDLE)" 2>/dev/null
	codesign --verify --deep --strict --verbose=2 "$(APP_BUNDLE)"

pkg: app
	rm -rf "$(PKG_ROOT)"
	mkdir -p "$(PKG_ROOT)/Applications"
	ditto "$(APP_BUNDLE)" "$(PKG_ROOT)/Applications/$(APP_DISPLAY_NAME).app"
	dot_clean -m "$(PKG_ROOT)"
	find "$(PKG_ROOT)" -name "._*" -delete
	find "$(PKG_ROOT)" -name ".DS_Store" -delete
	pkgbuild --root "$(PKG_ROOT)" --scripts "$(PKG_SCRIPTS)" --component-plist "$(PKG_COMPONENT_PLIST)" --identifier "$(PKG_IDENTIFIER)" --version "$(PKG_VERSION)" --install-location "/" "$(PKG)"

signed-pkg: require-developer-id-installer signed-app
	rm -rf "$(PKG_ROOT)"
	mkdir -p "$(PKG_ROOT)/Applications"
	ditto "$(APP_BUNDLE)" "$(PKG_ROOT)/Applications/$(APP_DISPLAY_NAME).app"
	dot_clean -m "$(PKG_ROOT)"
	find "$(PKG_ROOT)" -name "._*" -delete
	find "$(PKG_ROOT)" -name ".DS_Store" -delete
	pkgbuild --root "$(PKG_ROOT)" --scripts "$(PKG_SCRIPTS)" --component-plist "$(PKG_COMPONENT_PLIST)" --identifier "$(PKG_IDENTIFIER)" --version "$(PKG_VERSION)" --install-location "/" --sign "$(DEVELOPER_ID_INSTALLER)" "$(PKG)"
	pkgutil --check-signature "$(PKG)"

release-signed: signed-pkg
	mkdir -p "$(RELEASE_DIR)"
	cp "$(PKG)" "$(RELEASE_DIR)/$(APP_DISPLAY_NAME)-signed.pkg"
	ditto -c -k --sequesterRsrc --keepParent "$(PKG)" "$(RELEASE_DIR)/$(APP_DISPLAY_NAME)-signed.pkg.zip"
	@echo "Signed package: $(RELEASE_DIR)/$(APP_DISPLAY_NAME)-signed.pkg"
	@echo "Note: this skips notarization. For public distribution, use: make release"

notarize-pkg: signed-pkg
	xcrun notarytool submit "$(PKG)" --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple "$(PKG)"
	xcrun stapler validate "$(PKG)"
	spctl -a -vv -t install "$(PKG)"

release: release-notarized-pkg

release-notarized-pkg: notarize-pkg
	mkdir -p "$(RELEASE_DIR)"
	cp "$(PKG)" "$(RELEASE_DIR)/$(APP_DISPLAY_NAME).pkg"
	ditto -c -k --sequesterRsrc --keepParent "$(PKG)" "$(RELEASE_DIR)/$(APP_DISPLAY_NAME).pkg.zip"

app-zip: app
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(APP_ZIP)"

signed-app-zip: signed-app
	ditto -c -k --sequesterRsrc --keepParent "$(APP_BUNDLE)" "$(APP_ZIP)"

run: build
	$(BIN)

run-app: app
	open "$(APP_BUNDLE)"

install: app
	mkdir -p "$(INSTALL_DIR)"
	ditto "$(APP_BUNDLE)" "$(INSTALLED_APP)"
	open "$(INSTALL_DIR)"

clean:
	rm -rf $(BUILD_DIR)
