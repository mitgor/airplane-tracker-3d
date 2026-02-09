#!/bin/bash
# Build, sign, notarize, and create DMG for AirplaneTracker3D
#
# Usage:
#   ./Scripts/build-dmg.sh                    # Unsigned build (no Developer ID needed)
#   ./Scripts/build-dmg.sh --signed           # Signed + notarized (requires Apple Developer Program)
#
# Prerequisites:
#   - Xcode with command line tools installed
#   - For --signed: Apple Developer Program membership, "Developer ID Application" certificate
#   - For --signed: Run once: xcrun notarytool store-credentials "notary-airplanetracker"
#   - Optional: brew install create-dmg (for polished DMG layout)

set -euo pipefail

APP_NAME="AirplaneTracker3D"
SCHEME="AirplaneTracker3D"
PROJECT="${APP_NAME}.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/export"
DMG_NAME="${APP_NAME}.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
NOTARY_PROFILE="notary-airplanetracker"
SIGNED=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --signed) SIGNED=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

echo "=== AirplaneTracker3D Build Script ==="
echo "Mode: $(if $SIGNED; then echo 'Signed + Notarized'; else echo 'Unsigned'; fi)"
echo ""

# Clean build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 1: Archive
echo "--- Step 1: Archive ---"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

echo "Archive created at $ARCHIVE_PATH"

# Step 2: Export
echo "--- Step 2: Export ---"
if $SIGNED; then
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist ExportOptions.plist \
        -exportPath "$EXPORT_PATH" \
        -quiet
else
    # For unsigned: extract app directly from archive
    mkdir -p "$EXPORT_PATH"
    cp -R "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" "${EXPORT_PATH}/"

    # Ad-hoc sign with hardened runtime + entitlements (required for modern macOS)
    codesign --force --deep --sign - \
        --entitlements "${APP_NAME}/${APP_NAME}.entitlements" \
        --options runtime \
        "${EXPORT_PATH}/${APP_NAME}.app"
fi

echo "App exported to $EXPORT_PATH"

# Step 3: Create DMG
echo "--- Step 3: Create DMG ---"
if command -v create-dmg &>/dev/null; then
    # Polished DMG with create-dmg
    create-dmg \
        --volname "$APP_NAME" \
        --window-pos 200 120 \
        --window-size 600 400 \
        --icon "${APP_NAME}.app" 150 190 \
        --app-drop-link 450 190 \
        --icon-size 100 \
        --no-internet-enable \
        "$DMG_PATH" \
        "${EXPORT_PATH}/" || true
    # create-dmg returns non-zero if DMG already exists; || true handles that
else
    # Fallback: basic DMG with hdiutil
    echo "Note: Install create-dmg (brew install create-dmg) for a polished DMG layout."
    STAGING="${BUILD_DIR}/dmg-staging"
    mkdir -p "$STAGING"
    cp -R "${EXPORT_PATH}/${APP_NAME}.app" "$STAGING/"
    ln -s /Applications "$STAGING/Applications"

    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$STAGING" \
        -ov -format UDZO \
        "$DMG_PATH"

    rm -rf "$STAGING"
fi

echo "DMG created at $DMG_PATH"

# Step 4: Notarize (signed only)
if $SIGNED; then
    echo "--- Step 4: Notarize ---"
    xcrun notarytool submit "$DMG_PATH" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait

    echo "--- Step 5: Staple ---"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"

    echo ""
    echo "=== SUCCESS: Signed + notarized DMG ready ==="
    echo "File: $DMG_PATH"
    echo "Users can install by double-clicking the DMG."
else
    echo ""
    echo "=== SUCCESS: Unsigned DMG ready ==="
    echo "File: $DMG_PATH"
    echo ""
    echo "DISTRIBUTION NOTE:"
    echo "  Since this DMG is not notarized, users must:"
    echo "  1. Right-click the app and select 'Open' on first launch"
    echo "  2. Or: System Settings > Privacy & Security > Open Anyway"
    echo ""
    echo "  To create a notarized DMG:"
    echo "  1. Join Apple Developer Program (\$99/year)"
    echo "  2. Install 'Developer ID Application' certificate"
    echo "  3. Run: xcrun notarytool store-credentials 'notary-airplanetracker'"
    echo "  4. Run: ./Scripts/build-dmg.sh --signed"
fi
