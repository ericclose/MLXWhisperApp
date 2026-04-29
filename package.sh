#!/bin/bash
set -e

APP_NAME="MLXWhisperApp"
BUILD_DIR="build"
STAGING_DIR="dmg_staging"

# Extract version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" == "x86_64" ]; then
    ARCH="x64"
fi

DMG_NAME="${APP_NAME}.${ARCH}.${VERSION}.dmg"

# Check if build exists
if [ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    echo "Error: ${APP_NAME}.app not found in ${BUILD_DIR}. Please run build.sh first."
    exit 1
fi

echo "Creating DMG package..."

# Clean up previous staging
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"

# Copy the app
cp -R "${BUILD_DIR}/${APP_NAME}.app" "$STAGING_DIR/"

# Create symlink to Applications
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
rm -f "$DMG_NAME"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_NAME"

# Clean up
rm -rf "$STAGING_DIR"

# Move to Downloads only if not in CI
if [ -z "$GITHUB_ACTIONS" ]; then
    mkdir -p ~/Downloads
    mv "$DMG_NAME" ~/Downloads/
    echo "Location: ~/Downloads/${DMG_NAME}"
else
    echo "Location: ./${DMG_NAME}"
fi
echo "------------------------------------------------"
