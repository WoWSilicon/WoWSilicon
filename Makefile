APP_NAME := WoWSilicon
BINARY_NAME := WoWSilicon
BUILD_DIR := $(CURDIR)/.build
VERSION ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Packaging/Info.plist)
BUILD_NUMBER ?= $(shell /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Packaging/Info.plist)
RELEASE_BIN := $(BUILD_DIR)/arm64-apple-macosx/release/$(BINARY_NAME)
DEBUG_BIN := $(BUILD_DIR)/arm64-apple-macosx/debug/$(BINARY_NAME)
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
SPARKLE_FRAMEWORK := $(BUILD_DIR)/arm64-apple-macosx/release/Sparkle.framework
SPARKLE_ACCOUNT ?= com.wowsilicon.updates
SPARKLE_GENERATE_APPCAST := $(BUILD_DIR)/artifacts/sparkle/Sparkle/bin/generate_appcast
DOWNLOAD_URL_PREFIX ?= https://github.com/WoWSilicon/WoWSilicon/releases/download/v$(VERSION)/
CODESIGN_IDENTITY ?= -
ARCHIVE_DIR := $(BUILD_DIR)/release-archives
DMG_STAGING_DIR := $(BUILD_DIR)/dmg-staging
DMG_PATH := $(ARCHIVE_DIR)/$(APP_NAME)-$(VERSION).dmg
APPCAST_DIR := $(BUILD_DIR)/appcast
APPCAST_PATH := $(APPCAST_DIR)/appcast.xml
ICON_SRC := Sources/WoWSiliconSwift/Resources/Icons/turtlesilicon_icon.png
ICONSET := $(BUILD_DIR)/turtle.iconset
APP_ICON := $(BUILD_DIR)/turtle.icns
ICON_SCRIPT := $(BUILD_DIR)/make_icns.py
SWIFT_ENV := SWIFT_MODULECACHE_PATH="$(BUILD_DIR)/swift-module-cache" CLANG_MODULE_CACHE_PATH="$(BUILD_DIR)/clang-module-cache"
SWIFT_BUILD := $(SWIFT_ENV) swift build --arch arm64 --disable-sandbox --build-path "$(BUILD_DIR)" --cache-path "$(BUILD_DIR)/spm-cache" --manifest-cache none
RESOURCE_BUNDLE := $(BUILD_DIR)/arm64-apple-macosx/release/WoWSilicon-swift_WoWSiliconSwift.bundle
WINE_RUNTIME_DIR ?= $(CURDIR)/.wine-runtime

.PHONY: all build debug run bundle dmg appcast clean app_icon validate_wine_runtime

all: bundle

build:
	@echo "Building release binary..."
	$(SWIFT_BUILD) -c release

debug:
	@echo "Building debug binary..."
	$(SWIFT_BUILD) -c debug

xcode:
	@echo "Opening Xcode project..."
	tuist generate

run: bundle
	@echo "Launching $(APP_NAME).app..."
	open "$(APP_BUNDLE)"

validate_wine_runtime:
	@test -d "$(WINE_RUNTIME_DIR)" || (echo "Wine runtime not found at $(WINE_RUNTIME_DIR)" >&2; exit 1)
	@tools/wine-runtime/validate.sh --runtime "$(WINE_RUNTIME_DIR)"

bundle: build validate_wine_runtime
	@$(MAKE) app_icon
	@echo "Staging $(APP_NAME).app..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Frameworks"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp Packaging/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" "$(APP_BUNDLE)/Contents/Info.plist"
	@/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(BUILD_NUMBER)" "$(APP_BUNDLE)/Contents/Info.plist"
	@cp "$(RELEASE_BIN)" "$(APP_BUNDLE)/Contents/MacOS/$(BINARY_NAME)"
	@chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(BINARY_NAME)"
	@cp -R "$(SPARKLE_FRAMEWORK)" "$(APP_BUNDLE)/Contents/Frameworks/"
	@if [ -d "$(RESOURCE_BUNDLE)" ]; then \
		cp -R "$(RESOURCE_BUNDLE)" "$(APP_BUNDLE)/Contents/Resources/"; \
	else \
		echo "warning: resource bundle not found at $(RESOURCE_BUNDLE)"; \
		rsync -a Sources/WoWSiliconSwift/Resources/ "$(APP_BUNDLE)/Contents/Resources/"; \
	fi
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources/Wine"
	@cp -R "$(WINE_RUNTIME_DIR)/." "$(APP_BUNDLE)/Contents/Resources/Wine/"
	@find "$(APP_BUNDLE)/Contents/Resources/Wine" -name '.DS_Store' -delete
	@cp "$(APP_ICON)" "$(APP_BUNDLE)/Contents/Resources/turtle.icns"
	@xattr -cr "$(APP_BUNDLE)"
	@if [ -n "$(CODESIGN_IDENTITY)" ]; then \
		echo "Signing $(APP_BUNDLE) with identity $(CODESIGN_IDENTITY)..."; \
		codesign --force --deep --sign "$(CODESIGN_IDENTITY)" "$(APP_BUNDLE)"; \
	fi
	@echo "Bundle created at $(APP_BUNDLE)"

dmg: bundle
	@echo "Creating $(DMG_PATH)..."
	@rm -rf "$(DMG_STAGING_DIR)"
	@mkdir -p "$(DMG_STAGING_DIR)"
	@mkdir -p "$(ARCHIVE_DIR)"
	@cp -R "$(APP_BUNDLE)" "$(DMG_STAGING_DIR)/"
	@ln -s /Applications "$(DMG_STAGING_DIR)/Applications"
	@rm -f "$(DMG_PATH)"
	@hdiutil create -volname "$(APP_NAME)" -fs HFS+ -format UDZO -srcfolder "$(DMG_STAGING_DIR)" "$(DMG_PATH)" >/dev/null
	@echo "DMG created at $(DMG_PATH)"

appcast: dmg
	@echo "Generating Sparkle appcast..."
	@test -x "$(SPARKLE_GENERATE_APPCAST)" || (echo "Sparkle generate_appcast not found. Run swift build first." >&2; exit 1)
	@rm -rf "$(APPCAST_DIR)"
	@mkdir -p "$(APPCAST_DIR)"
	@cp "$(DMG_PATH)" "$(APPCAST_DIR)/"
	@if [ -n "$${RELEASE_NOTES_FILE:-}" ] && [ -f "$${RELEASE_NOTES_FILE}" ]; then \
		cp "$${RELEASE_NOTES_FILE}" "$(APPCAST_DIR)/$(APP_NAME)-$(VERSION).md"; \
	else \
		printf '# WoWSilicon %s\n\nSee the GitHub release for changes.\n' "$(VERSION)" > "$(APPCAST_DIR)/$(APP_NAME)-$(VERSION).md"; \
	fi
	@if [ -n "$${EXISTING_APPCAST:-}" ] && [ -f "$${EXISTING_APPCAST}" ]; then \
		cp "$${EXISTING_APPCAST}" "$(APPCAST_PATH)"; \
	fi
	@if [ -n "$${SPARKLE_PRIVATE_KEY:-}" ]; then \
		printf '%s' "$${SPARKLE_PRIVATE_KEY}" | "$(SPARKLE_GENERATE_APPCAST)" \
			--ed-key-file - \
			--embed-release-notes \
			--download-url-prefix "$(DOWNLOAD_URL_PREFIX)" \
			--link "https://wowsilicon.github.io/" \
			"$(APPCAST_DIR)"; \
	else \
		"$(SPARKLE_GENERATE_APPCAST)" \
			--account "$(SPARKLE_ACCOUNT)" \
			--embed-release-notes \
			--download-url-prefix "$(DOWNLOAD_URL_PREFIX)" \
			--link "https://wowsilicon.github.io/" \
			"$(APPCAST_DIR)"; \
	fi
	@echo "Appcast generated at $(APPCAST_PATH)"

clean:
	@echo "Cleaning build artifacts..."
	@swift package clean
	@rm -rf "$(BUILD_DIR)"

app_icon: $(APP_ICON)

$(APP_ICON): $(ICON_SRC)
	@echo "Generating app icon..."
	@rm -rf "$(ICONSET)"
	@mkdir -p "$(ICONSET)"
	@sips -z 16 16 "$<" --out "$(ICONSET)/icon_16x16.png" >/dev/null
	@sips -z 32 32 "$<" --out "$(ICONSET)/icon_16x16@2x.png" >/dev/null
	@sips -z 32 32 "$<" --out "$(ICONSET)/icon_32x32.png" >/dev/null
	@sips -z 64 64 "$<" --out "$(ICONSET)/icon_32x32@2x.png" >/dev/null
	@sips -z 64 64 "$<" --out "$(ICONSET)/icon_64x64.png" >/dev/null
	@sips -z 128 128 "$<" --out "$(ICONSET)/icon_64x64@2x.png" >/dev/null
	@sips -z 128 128 "$<" --out "$(ICONSET)/icon_128x128.png" >/dev/null
	@sips -z 256 256 "$<" --out "$(ICONSET)/icon_128x128@2x.png" >/dev/null
	@sips -z 256 256 "$<" --out "$(ICONSET)/icon_256x256.png" >/dev/null
	@sips -z 512 512 "$<" --out "$(ICONSET)/icon_256x256@2x.png" >/dev/null
	@sips -z 512 512 "$<" --out "$(ICONSET)/icon_512x512.png" >/dev/null
	@sips -z 1024 1024 "$<" --out "$(ICONSET)/icon_512x512@2x.png" >/dev/null
	@printf '{\n  "images" : [\n    { "idiom" : "mac", "size" : "16x16", "filename" : "icon_16x16.png", "scale" : "1x" },\n    { "idiom" : "mac", "size" : "16x16", "filename" : "icon_16x16@2x.png", "scale" : "2x" },\n    { "idiom" : "mac", "size" : "32x32", "filename" : "icon_32x32.png", "scale" : "1x" },\n    { "idiom" : "mac", "size" : "32x32", "filename" : "icon_32x32@2x.png", "scale" : "2x" },\n    { "idiom" : "mac", "size" : "64x64", "filename" : "icon_64x64.png", "scale" : "1x" },\n    { "idiom" : "mac", "size" : "64x64", "filename" : "icon_64x64@2x.png", "scale" : "2x" },\n    { "idiom" : "mac", "size" : "128x128", "filename" : "icon_128x128.png", "scale" : "1x" },\n    { "idiom" : "mac", "size" : "128x128", "filename" : "icon_128x128@2x.png", "scale" : "2x" },\n    { "idiom" : "mac", "size" : "256x256", "filename" : "icon_256x256.png", "scale" : "1x" },\n    { "idiom" : "mac", "size" : "256x256", "filename" : "icon_256x256@2x.png", "scale" : "2x" },\n    { "idiom" : "mac", "size" : "512x512", "filename" : "icon_512x512.png", "scale" : "1x" },\n    { "idiom" : "mac", "size" : "512x512", "filename" : "icon_512x512@2x.png", "scale" : "2x" }\n  ],\n  "info" : { "version" : 1, "author" : "xcode" }\n}\n' > "$(ICONSET)/Contents.json"
	@printf '%s\n' \
	'import struct' \
	'from pathlib import Path' \
	'' \
	'iconset = Path("$(ICONSET)")' \
	'entries = [' \
	'    ("icp4", "icon_16x16.png"),' \
	'    ("icp5", "icon_32x32.png"),' \
	'    ("icp6", "icon_64x64.png"),' \
	'    ("ic07", "icon_128x128.png"),' \
	'    ("ic11", "icon_32x32@2x.png"),' \
	'    ("ic12", "icon_64x64@2x.png"),' \
	'    ("ic08", "icon_256x256.png"),' \
	'    ("ic13", "icon_256x256@2x.png"),' \
	'    ("ic09", "icon_512x512.png"),' \
	'    ("ic10", "icon_512x512@2x.png"),' \
	'    ("ic14", "icon_512x512@2x.png"),' \
	']' \
	'' \
	'chunks = []' \
	'total = 8' \
	'for typ, name in entries:' \
	'    data = (iconset / name).read_bytes()' \
	'    chunk = typ.encode("ascii") + struct.pack(">I", len(data) + 8) + data' \
	'    chunks.append(chunk)' \
	'    total += len(chunk)' \
	'' \
	'Path("$(APP_ICON)").write_bytes(' \
	'    b"icns" + struct.pack(">I", total) + b"".join(chunks)' \
	')' \
	> "$(ICON_SCRIPT)"
	@python3 "$(ICON_SCRIPT)"
	@rm -f "$(ICON_SCRIPT)"
	@rm -rf "$(ICONSET)"
