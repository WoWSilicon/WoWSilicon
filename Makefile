APP_NAME := WoWSilicon
BINARY_NAME := WoWSilicon
BUILD_DIR := $(CURDIR)/.build
RELEASE_BIN := $(BUILD_DIR)/arm64-apple-macosx/release/$(BINARY_NAME)
DEBUG_BIN := $(BUILD_DIR)/arm64-apple-macosx/debug/$(BINARY_NAME)
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
ICON_SRC := Sources/WoWSiliconSwift/Resources/Icons/turtlesilicon_icon.png
ICONSET := $(BUILD_DIR)/turtle.iconset
APP_ICON := $(BUILD_DIR)/turtle.icns
ICON_SCRIPT := $(BUILD_DIR)/make_icns.py
SWIFT_ENV := SWIFT_MODULECACHE_PATH="$(BUILD_DIR)/swift-module-cache" CLANG_MODULE_CACHE_PATH="$(BUILD_DIR)/clang-module-cache"
SWIFT_BUILD := $(SWIFT_ENV) swift build --arch arm64 --disable-sandbox --build-path "$(BUILD_DIR)" --cache-path "$(BUILD_DIR)/spm-cache" --manifest-cache none
RESOURCE_BUNDLE := $(BUILD_DIR)/arm64-apple-macosx/release/WoWSilicon-swift_WoWSiliconSwift.bundle

.PHONY: all build debug run bundle clean app_icon

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

run: build
	@echo "Launching $(BINARY_NAME)..."
	$(RELEASE_BIN)

bundle: build
	@$(MAKE) app_icon
	@echo "Staging $(APP_NAME).app..."
	@rm -rf "$(APP_BUNDLE)"
	@mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	@mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	@cp Packaging/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	@cp "$(RELEASE_BIN)" "$(APP_BUNDLE)/Contents/MacOS/$(BINARY_NAME)"
	@chmod +x "$(APP_BUNDLE)/Contents/MacOS/$(BINARY_NAME)"
	@if [ -d "$(RESOURCE_BUNDLE)" ]; then \
		cp -R "$(RESOURCE_BUNDLE)" "$(APP_BUNDLE)/Contents/Resources/"; \
	else \
		echo "warning: resource bundle not found at $(RESOURCE_BUNDLE)"; \
		rsync -a Sources/WoWSiliconSwift/Resources/ "$(APP_BUNDLE)/Contents/Resources/"; \
	fi
	@cp "$(APP_ICON)" "$(APP_BUNDLE)/Contents/Resources/turtle.icns"
	@echo "Bundle created at $(APP_BUNDLE)"

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
