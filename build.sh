#!/bin/bash
set -e

APP_NAME="MLXWhisperApp"
APP_DIR="build/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
EMBEDDED_PYTHON_DIR="embedded_python"

echo "Checking embedded Python..."
if [ ! -d "$EMBEDDED_PYTHON_DIR" ]; then
    echo "Downloading embedded Python (this will take a few minutes)..."
    curl -L "https://github.com/astral-sh/python-build-standalone/releases/download/20260414/cpython-3.12.13%2B20260414-aarch64-apple-darwin-install_only.tar.gz" -o python.tar.gz
    
    echo "Extracting Python..."
    mkdir -p "$EMBEDDED_PYTHON_DIR"
    tar -xzf python.tar.gz -C "$EMBEDDED_PYTHON_DIR" --strip-components=1
    rm python.tar.gz
    
    echo "Installing MLX and Whisper dependencies into embedded Python..."
    # Ensure pip is up to date
    "$EMBEDDED_PYTHON_DIR/bin/python3" -m ensurepip || true
    "$EMBEDDED_PYTHON_DIR/bin/python3" -m pip install --upgrade pip
    
    # Install MLX and FFmpeg dependencies from requirements.txt
    "$EMBEDDED_PYTHON_DIR/bin/python3" -m pip install -r Python/requirements.txt
fi

echo "Extracting native FFmpeg from Python package..."
FFMPEG_SRC=$("$EMBEDDED_PYTHON_DIR/bin/python3" -c "import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())")
cp "$FFMPEG_SRC" ./ffmpeg
chmod +x ./ffmpeg

echo "Cleaning previous build..."
rm -rf build
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Compiling Swift files..."
xcrun -sdk macosx swiftc \
    Sources/*.swift \
    -o "${MACOS_DIR}/${APP_NAME}" \
    -target arm64-apple-macosx14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework Combine \
    -framework UniformTypeIdentifiers

echo "Copying resources..."
cp Python/transcribe.py "${RESOURCES_DIR}/"
cp ffmpeg "${RESOURCES_DIR}/"
cp AppIcon.icns "${RESOURCES_DIR}/"
cp Info.plist "${CONTENTS_DIR}/"
# Update Info.plist if not already set
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "${CONTENTS_DIR}/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "${CONTENTS_DIR}/Info.plist"

echo "Copying embedded Python into App Bundle..."
cp -R "$EMBEDDED_PYTHON_DIR" "${RESOURCES_DIR}/python"

echo "Optimizing Python environment size..."
PYTHON_LIB_DIR="${RESOURCES_DIR}/python/lib/python3.12"

# Remove cache files
find "${RESOURCES_DIR}/python" -name "__pycache__" -exec rm -rf {} +
find "${RESOURCES_DIR}/python" -name "*.pyc" -delete

# Remove unnecessary directories
rm -rf "${RESOURCES_DIR}/python/include"
rm -rf "${RESOURCES_DIR}/python/share"
rm -rf "${PYTHON_LIB_DIR}/test"
rm -rf "${PYTHON_LIB_DIR}/site-packages/pip"
rm -rf "${PYTHON_LIB_DIR}/site-packages/setuptools"

# Remove heavy packages that are not strictly required for MLX inference
# NOTE: Keeping torch and scipy for maximum compatibility
rm -rf "${PYTHON_LIB_DIR}/site-packages/sympy"

echo "Codesigning..."
# We must sign all embedded binaries inside the python directory as well
# Deep signing usually handles this, but it's safer to sign everything manually first
find "${RESOURCES_DIR}/python" -type f -perm +111 -exec codesign --force --sign - {} + 2>/dev/null || true
codesign --force --deep --sign - --entitlements MLXWhisperApp.entitlements "${APP_DIR}"

echo "Build complete! App is located at ${APP_DIR}"
