#!/bin/bash
set -e

WORKSPACE_DIR="/Users/kushhooda/Documents/Applications/CanvasMac"
APP_PATH="/Users/kushhooda/Library/Developer/Xcode/DerivedData/Canvas-abddnybcmwhgydbsaljqeqrakwwf/Build/Products/Release/Canvas.app"
ENTITLEMENTS="$WORKSPACE_DIR/app/Canvas/Canvas.entitlements"
IDENTITY="Apple Development: kush9hooda@icloud.com (KW6Y58ARX2)"
FINAL_DMG="$WORKSPACE_DIR/Canvas.dmg"

echo "▶ Step 1: Building Release..."
xcodebuild -project "$WORKSPACE_DIR/app/Canvas.xcodeproj" \
    -scheme Canvas -configuration Release 2>&1 \
    | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:" | head -5

echo "▶ Step 2: Re-signing all nested frameworks with consistent identity..."
# Sign nested bundles deepest-first so outer seal is valid
find "$APP_PATH" \( -name "*.framework" -o -name "*.dylib" -o -name "*.xpc" -o -name "*.app" \) \
    | sort -r \
    | while read f; do
        codesign --force --sign "$IDENTITY" --timestamp=none "$f" 2>/dev/null
    done

# Sign outer app with entitlements
codesign --force --sign "$IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp=none \
    "$APP_PATH"

codesign -vv "$APP_PATH" 2>&1 | grep -E "valid|Authority"
echo "✓ Signing complete"

echo "▶ Step 3: Packaging DMG..."
rm -f "$FINAL_DMG" "$WORKSPACE_DIR"/Canvas\ *.dmg 2>/dev/null || true

npx create-dmg \
    --overwrite \
    --no-code-sign \
    --dmg-title="Canvas" \
    "$APP_PATH" \
    "$WORKSPACE_DIR/"

# Rename versioned output
VERSIONED=$(ls "$WORKSPACE_DIR"/Canvas\ *.dmg 2>/dev/null | head -1)
[ -n "$VERSIONED" ] && mv "$VERSIONED" "$FINAL_DMG"

echo "✅ Done: $FINAL_DMG"
