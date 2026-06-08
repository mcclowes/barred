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

# Regenerate Xcode project if xcodegen is available
if command -v xcodegen &>/dev/null && [ -f project.yml ]; then
    xcodegen generate
fi

xcodebuild -project Barred.xcodeproj -scheme Barred -configuration Release \
    CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
    CONFIGURATION_BUILD_DIR="$BUILD_DIR/release" \
    build

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable from xcodebuild output
cp "$BUILD_DIR/release/Barred.app/Contents/MacOS/Barred" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Copy Info.plist and resolve Xcode build variables
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.mcclowes.barred" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION:-1.0.0}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-1}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :LSMinimumSystemVersion 14.0" "$APP_BUNDLE/Contents/Info.plist"

# Compile the app icon from the Icon Composer file (generates barred.icns + Assets.car)
if [ -d "$PROJECT_DIR/barred.icon" ]; then
    echo "Compiling app icon..."
    xcrun actool "$PROJECT_DIR/barred.icon" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon barred \
        --output-partial-info-plist /tmp/barred-asset-info.plist
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Code signing — use CODESIGN_IDENTITY env var, or fall back to "Barred Dev" local cert, then ad-hoc
SIGN_IDENTITY="${CODESIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
ENTITLEMENTS="$PROJECT_DIR/Resources/Barred.entitlements"
KEYCHAIN_ARG=""

if [ -n "${KEYCHAIN_PATH:-}" ]; then
    KEYCHAIN_ARG="--keychain $KEYCHAIN_PATH"
fi

if [ -z "$SIGN_IDENTITY" ] && security find-identity -v -p codesigning | grep -q "Barred Dev"; then
    SIGN_IDENTITY="Barred Dev"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing app with: $SIGN_IDENTITY"
    # Sign the main executable first, then the bundle (avoid deprecated --deep)
    codesign --force --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        --options runtime \
        --timestamp \
        $KEYCHAIN_ARG \
        "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    codesign --force --sign "$SIGN_IDENTITY" \
        --entitlements "$ENTITLEMENTS" \
        --options runtime \
        --timestamp \
        $KEYCHAIN_ARG \
        "$APP_BUNDLE"

    echo "Verifying signature..."
    codesign --verify --strict "$APP_BUNDLE"
    echo "Checking notarization requirements..."
    spctl --assess --type execute --verbose "$APP_BUNDLE" || echo "  (spctl check expected to fail pre-notarization)"
else
    echo "Warning: No signing identity found. Using ad-hoc signing (permissions may reset on rebuild)."
    echo "  Create a local cert named 'Barred Dev' in Keychain Access to fix this."
    codesign --force --sign - "$APP_BUNDLE"
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
