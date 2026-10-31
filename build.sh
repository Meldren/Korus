#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="Korus"
BUNDLE_ID="com.meldren.korus"

BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
CONTENTS="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS}/MacOS"
RESOURCES_DIR="${CONTENTS}/Resources"

echo "==> Cleaning previous build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

echo "==> Compiling Swift sources..."
swiftc -O -whole-module-optimization \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk \
  -target arm64-apple-macos14.4 \
  -swift-version 5 \
  -parse-as-library \
  Sources/**/*.swift \
  -o "${MACOS_DIR}/${APP_NAME}"

echo "==> Building application icon..."
ICONSET_TMP="$(mktemp -d)/${APP_NAME}.iconset"
mkdir -p "${ICONSET_TMP}"
cp Resources/Assets.xcassets/AppIcon.appiconset/*.png "${ICONSET_TMP}/"
iconutil -c icns "${ICONSET_TMP}" -o "${RESOURCES_DIR}/AppIcon.icns"
rm -rf "$(dirname "${ICONSET_TMP}")"

echo "==> Generating Info.plist..."
sed \
  -e "s/\$(EXECUTABLE_NAME)/${APP_NAME}/g" \
  -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/${BUNDLE_ID}/g" \
  -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
  Resources/Info.plist > "${CONTENTS}/Info.plist"

/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS}/Info.plist" 2>/dev/null || true

echo "==> Ad-hoc code signing with entitlements..."
codesign --force --sign - --entitlements Resources/Korus.entitlements "${APP_BUNDLE}"

echo "==> Build complete: ${APP_BUNDLE}"
