#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/.build"
APP_NAME="Barred"
OUTPUT_APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
OUTPUT_ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
BUILT_PLIST="$BUILD_DIR/release/$APP_NAME.app/Contents/Info.plist"

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

if [ ! -f "$BUILT_PLIST" ]; then
    echo "Built app metadata not found: $BUILT_PLIST" >&2
    exit 1
fi

echo "Creating app bundle..."
if [ -d "$OUTPUT_ZIP_PATH" ]; then
    echo 'The ZIP destination is a directory.' >&2
    exit 1
fi
path_exists() {
    [ -e "$1" ] || [ -L "$1" ]
}

restore_artifact() {
    local destination="$1" backup="$2" promotion_started="$3"
    if path_exists "$backup"; then
        if ! rm -rf "$destination" || ! mv -f "$backup" "$destination"; then
            echo "Could not restore previous artifact: $destination" >&2
            return 1
        fi
    elif [ "$promotion_started" -eq 1 ]; then
        if ! rm -rf "$destination"; then
            echo "Could not remove incomplete artifact: $destination" >&2
            return 1
        fi
    fi
    return 0
}

cleanup_package() {
    local original_status=$? restore_failed=0
    trap - EXIT
    trap '' HUP INT TERM
    set +e
    if [ "$original_status" -ne 0 ] && [ "$PACKAGE_PROMOTION_STARTED" -eq 1 ]; then
        restore_artifact "$OUTPUT_APP_BUNDLE" "$PREVIOUS_APP_BUNDLE" "$APP_PROMOTION_STARTED" || restore_failed=1
        restore_artifact "$OUTPUT_ZIP_PATH" "$PREVIOUS_ZIP_PATH" "$ZIP_PROMOTION_STARTED" || restore_failed=1
    fi
    if [ "$restore_failed" -ne 0 ]; then
        echo "Packaging recovery files retained at: $PACKAGE_STAGING" >&2
    elif ! rm -rf "$PACKAGE_STAGING"; then
        echo "Could not remove packaging staging: $PACKAGE_STAGING" >&2
    fi
    exit "$original_status"
}

PACKAGE_PROMOTION_STARTED=0
APP_PROMOTION_STARTED=0
ZIP_PROMOTION_STARTED=0
PACKAGE_STAGING=$(mktemp -d "$BUILD_DIR/.barred-package.XXXXXX")
PREVIOUS_APP_BUNDLE="$PACKAGE_STAGING/previous-$APP_NAME.app"
PREVIOUS_ZIP_PATH="$PACKAGE_STAGING/previous-$APP_NAME.zip"
trap cleanup_package EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
APP_BUNDLE="$PACKAGE_STAGING/$APP_NAME.app"
ZIP_PATH="$PACKAGE_STAGING/$APP_NAME.zip"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable from xcodebuild output
cp "$BUILD_DIR/release/Barred.app/Contents/MacOS/Barred" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Preserve Xcode's resolved metadata unless packaging overrides are explicit.
cp "$BUILT_PLIST" "$APP_BUNDLE/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_BUNDLE/Contents/Info.plist"
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_BUNDLE/Contents/Info.plist"
fi

# Compile the app icon from the Icon Composer file (generates barred.icns + Assets.car)
if [ -d "$PROJECT_DIR/barred.icon" ]; then
    echo "Compiling app icon..."
    xcrun actool "$PROJECT_DIR/barred.icon" \
        --compile "$APP_BUNDLE/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --app-icon barred \
        --output-partial-info-plist "$PACKAGE_STAGING/asset-info.plist"
fi

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Code signing — use CODESIGN_IDENTITY env var, or fall back to "Barred Dev" local cert, then ad-hoc
SIGN_IDENTITY="${CODESIGN_IDENTITY:-${DEVELOPER_ID_APPLICATION:-}}"
ENTITLEMENTS="$PROJECT_DIR/Resources/Barred.entitlements"

if [ -z "$SIGN_IDENTITY" ] && security find-identity -v -p codesigning | grep -q "Barred Dev"; then
    SIGN_IDENTITY="Barred Dev"
fi

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing app with: $SIGN_IDENTITY"
    SIGN_ARGS=(--force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" --options runtime --timestamp)
    if [ -n "${KEYCHAIN_PATH:-}" ]; then
        SIGN_ARGS+=(--keychain "$KEYCHAIN_PATH")
    fi
    # Sign the main executable first, then the bundle (avoid deprecated --deep)
    codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

    codesign "${SIGN_ARGS[@]}" "$APP_BUNDLE"

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
create_archive() {
    rm -f "$ZIP_PATH"
    (cd "$PACKAGE_STAGING" && ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH")
    unzip -tq "$ZIP_PATH" >/dev/null
}
create_archive

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
    create_archive
else
    echo "Skipping notarization (credentials not set)"
fi

PACKAGE_HASH=$(shasum -a 256 "$ZIP_PATH")
PACKAGE_HASH=${PACKAGE_HASH%% *}

# Keep recoverable originals until both replacements have been published.
PACKAGE_PROMOTION_STARTED=1
if path_exists "$OUTPUT_APP_BUNDLE"; then
    mv "$OUTPUT_APP_BUNDLE" "$PREVIOUS_APP_BUNDLE"
fi
if path_exists "$OUTPUT_ZIP_PATH"; then
    mv "$OUTPUT_ZIP_PATH" "$PREVIOUS_ZIP_PATH"
fi
APP_PROMOTION_STARTED=1
mv "$APP_BUNDLE" "$OUTPUT_APP_BUNDLE"
ZIP_PROMOTION_STARTED=1
mv -f "$ZIP_PATH" "$OUTPUT_ZIP_PATH"

echo ""
echo "Done! Outputs:"
echo "  App:  $OUTPUT_APP_BUNDLE"
echo "  Zip:  $OUTPUT_ZIP_PATH"
echo ""
echo "SHA256: $PACKAGE_HASH"
echo ""
echo "Note: You'll need to grant Accessibility access in"
echo "  System Settings > Privacy & Security > Accessibility"
