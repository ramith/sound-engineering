#!/bin/bash
# Build AdaptiveSound as a proper macOS app bundle

set -e

echo "🔨 Building AdaptiveSound..."
swift build -c debug

BUILD_DIR=".build/debug"
APP_BUNDLE="$BUILD_DIR/AdaptiveSound.app"
EXECUTABLE="$BUILD_DIR/AdaptiveSound"

echo "📦 Creating app bundle structure..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

echo "📋 Copying Info.plist..."
cp "Sources/AdaptiveSound/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

echo "📂 Copying executable..."
cp "$EXECUTABLE" "$APP_BUNDLE/Contents/MacOS/AdaptiveSound"
chmod +x "$APP_BUNDLE/Contents/MacOS/AdaptiveSound"

echo "✅ App bundle created: $APP_BUNDLE"
echo ""
echo "🚀 Launching app..."
open "$APP_BUNDLE"

echo "✓ App should now appear in Dock and Command+Tab switcher!"
