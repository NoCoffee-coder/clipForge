#!/bin/bash
# ClipForge build script — compiles Swift sources into a macOS .app bundle
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCES_DIR="$PROJECT_DIR/Sources"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/ClipForge.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
INFO_PLIST="$PROJECT_DIR/Info.plist"

SDK=$(xcrun --show-sdk-path)
TARGET="arm64-apple-macosx13.0"

# Collect all Swift sources
SOURCES=$(find "$SOURCES_DIR" -name "*.swift" | sort | tr '\n' ' ')

echo "→ Compiling ClipForge (Swift)..."
echo "  SDK: $SDK"
echo "  Sources: $SOURCES"

# Clean + prepare bundle
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RES_DIR"

# Compile
swiftc -parse-as-library \
    -sdk "$SDK" \
    -target "$TARGET" \
    -framework AppKit \
    -framework SwiftUI \
    -framework Foundation \
    -framework Carbon \
    -framework Combine \
    -O \
    -o "$MACOS_DIR/ClipForge" \
    $SOURCES

# Copy Info.plist
cp "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"

# Copy icon if present; otherwise generate AppIcon.icns from resource/icon.png
if [ -f "$PROJECT_DIR/resource/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/resource/AppIcon.icns" "$RES_DIR/"
elif [ -f "$PROJECT_DIR/resource/icon.png" ]; then
    echo "-> Generating AppIcon.icns from resource/icon.png..."
    ICONSET="$BUILD_DIR/AppIcon.iconset"
    rm -rf "$ICONSET"
    mkdir -p "$ICONSET"
    # Center-crop to square (icons must be square; source may not be)
    SRC_W=$(sips -g pixelWidth "$PROJECT_DIR/resource/icon.png" | awk '/pixelWidth/{print $2}')
    SRC_H=$(sips -g pixelHeight "$PROJECT_DIR/resource/icon.png" | awk '/pixelHeight/{print $2}')
    MIN=$(( SRC_W < SRC_H ? SRC_W : SRC_H ))
    SQUARE="$BUILD_DIR/icon_square.png"
    sips -c "$MIN" "$MIN" "$PROJECT_DIR/resource/icon.png" --out "$SQUARE" >/dev/null
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$SQUARE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$SQUARE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$RES_DIR/AppIcon.icns"
    rm -f "$SQUARE"
fi

# Menu bar icon (loaded by name at runtime)
[ -f "$PROJECT_DIR/resource/menu_icon.png" ] && \
    cp "$PROJECT_DIR/resource/menu_icon.png" "$RES_DIR/"

# Ad-hoc codesign (no Developer ID required for local run)
codesign -s - --deep --force "$APP_DIR" 2>/dev/null || true

echo "✓ Build complete: $APP_DIR"
echo "  Run: open \"$APP_DIR\""
