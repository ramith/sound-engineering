#!/bin/bash
# Convert PNG to macOS .icns format using iconutil

set -e

ICON_DIR="Sources/AdaptiveSound/Assets.xcassets/AppIcon.appiconset"
ICONSET_TEMP="/tmp/AppIcon.iconset"
OUTPUT_ICNS="$ICON_DIR/AppIcon.icns"

echo "🎨 Converting PNG to macOS .icns format..."

# Create iconset directory
mkdir -p "$ICONSET_TEMP"

# Copy and rename PNGs for iconset (iconutil expects specific names)
# 512×512 @1x
cp "$ICON_DIR/app-icon-512.png" "$ICONSET_TEMP/icon_512x512.png"
# 1024×1024 @2x
cp "$ICON_DIR/app-icon-1024.png" "$ICONSET_TEMP/icon_512x512@2x.png"

# Also create smaller sizes for completeness (scale down)
sips -z 256 256 "$ICON_DIR/app-icon-512.png" --out "$ICONSET_TEMP/icon_256x256.png" 2>/dev/null
sips -z 256 512 "$ICON_DIR/app-icon-1024.png" --out "$ICONSET_TEMP/icon_256x256@2x.png" 2>/dev/null
sips -z 128 128 "$ICON_DIR/app-icon-512.png" --out "$ICONSET_TEMP/icon_128x128.png" 2>/dev/null
sips -z 128 256 "$ICON_DIR/app-icon-1024.png" --out "$ICONSET_TEMP/icon_128x128@2x.png" 2>/dev/null

# Convert iconset to icns
iconutil -c icns -o "$OUTPUT_ICNS" "$ICONSET_TEMP"

echo "✅ Created: $OUTPUT_ICNS"
rm -rf "$ICONSET_TEMP"
