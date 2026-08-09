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

# Copy icon if present
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RES_DIR/"
fi

# Ad-hoc codesign (no Developer ID required for local run)
codesign -s - --deep --force "$APP_DIR" 2>/dev/null || true

echo "✓ Build complete: $APP_DIR"
echo "  Run: open \"$APP_DIR\""
