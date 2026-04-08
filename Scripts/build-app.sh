#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Barred"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"

# Optional signing config (set these env vars for signed builds)
# DEVELOPER_ID_APPLICATION  — e.g. "Developer ID Application: Your Name (TEAMID)"
# APPLE_ID                  — your Apple ID email
# APPLE_ID_PASSWORD         — app-specific password
# APPLE_TEAM_ID             — your 10-char team ID

echo "Building $APP_NAME..."
cd "$PROJECT_DIR"
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/release/Barred" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# Copy app icon if present
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Code signing — use CODESIGN_IDENTITY env var, or fall back to "Barred Dev" local cert, then ad-hoc
SIGN_IDENTITY="${CODESIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"

if [ -z "$SIGN_IDENTITY" ] && security find-identity -v -p codesigning | grep -q "Barred Dev"; then
    SIGN_IDENTITY="Barred Dev"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing app with: $SIGN_IDENTITY"
    codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
    echo "Verifying signature..."
    codesign --verify --deep --strict "$APP_BUNDLE"
else
    echo "Warning: No signing identity found. Using ad-hoc signing (permissions may reset on rebuild)."
    echo "  Create a local cert named 'Barred Dev' in Keychain Access to fix this."
    codesign --force --deep --sign - "$APP_BUNDLE"
fi

# Create zip for distribution
echo "Creating zip archive..."
cd "$BUILD_DIR"
rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
cd "$PROJECT_DIR"

# Notarization
if [ -n "${DEVELOPER_ID_APPLICATION:-}" ] && [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_ID_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
    echo "Submitting for notarization..."
    xcrun notarytool submit "$ZIP_PATH" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_ID_PASSWORD" \
        --team-id "$APPLE_TEAM_ID" \
        --wait

    echo "Stapling notarization ticket..."
    xcrun stapler staple "$APP_BUNDLE"

    # Re-zip after stapling
    echo "Re-creating zip with stapled ticket..."
    rm -f "$ZIP_PATH"
    cd "$BUILD_DIR"
    ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"
    cd "$PROJECT_DIR"
else
    echo "Skipping notarization (credentials not set)"
fi

echo ""
echo "Done! Outputs:"
echo "  App:  $APP_BUNDLE"
echo "  Zip:  $ZIP_PATH"
echo ""
echo "SHA256: $(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo ""
echo "Note: You'll need to grant Accessibility access in"
echo "  System Settings > Privacy & Security > Accessibility"
