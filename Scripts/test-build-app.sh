#!/bin/bash
# Exercise the build helper with isolated files and stubbed signing tools.
set -euo pipefail
unset VERSION BUILD_NUMBER

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/barred-build-helper.XXXXXX")
trap 'rm -rf "$barred_test_temp"' EXIT

fail() { echo "$1" >&2; exit 1; }

new_fixture() {
    barred_fixture=$(mktemp -d "$barred_test_temp/project with spaces.XXXXXX")
    mkdir -p "$barred_fixture/Scripts" "$barred_fixture/Resources" "$barred_fixture/bin"
    cp "$barred_test_source/Scripts/build-app.sh" "$barred_fixture/Scripts/"
    cp "$barred_test_source/Resources/Info.plist" "$barred_fixture/Resources/"
    touch "$barred_fixture/Resources/Barred.entitlements" "$barred_fixture/project.yml"

    cat > "$barred_fixture/bin/xcodegen" <<'STUB'
#!/bin/bash
echo generate >> "$HELPER_LOG"
STUB

    cat > "$barred_fixture/bin/xcodebuild" <<'STUB'
#!/bin/bash
set -eu
echo build >> "$HELPER_LOG"
for argument in "$@"; do
    if [[ "$argument" == CONFIGURATION_BUILD_DIR=* ]]; then
        output="${argument#CONFIGURATION_BUILD_DIR=}"
    fi
done
mkdir -p "$output/Barred.app/Contents/MacOS"
echo fixture > "$output/Barred.app/Contents/MacOS/Barred"
if [ "${OMIT_BUILT_PLIST:-0}" = 0 ]; then
    cp Resources/Info.plist "$output/Barred.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Barred' "$output/Barred.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.mcclowes.barred' "$output/Barred.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 4.5.6' "$output/Barred.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleVersion 78' "$output/Barred.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :LSMinimumSystemVersion 14.2' "$output/Barred.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName BuiltBarred' "$output/Barred.app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Add :DTSDKName string macosx26.0' "$output/Barred.app/Contents/Info.plist"
fi
STUB

    cat > "$barred_fixture/bin/codesign" <<'STUB'
#!/bin/bash
set -eu
if [ "$1" = --verify ]; then
    echo verify >> "$HELPER_LOG"
    exit "${VERIFY_STATUS:-0}"
fi
echo sign >> "$HELPER_LOG"
keychain=''
keychain_count=0
identity=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        --keychain) keychain="$2"; keychain_count=$((keychain_count + 1)); shift ;;
        --sign) identity="$2"; shift ;;
    esac
    shift
done
if [ "$keychain" != "$EXPECTED_KEYCHAIN" ]; then
    echo "Expected exact keychain: $EXPECTED_KEYCHAIN; received: $keychain" >&2
    exit 31
fi
expected_count=0
[ -z "$EXPECTED_KEYCHAIN" ] || expected_count=1
[ "$keychain_count" = "$expected_count" ] || exit 34
[ "$identity" = "$EXPECTED_IDENTITY" ] || exit 32
STUB

    cat > "$barred_fixture/bin/security" <<'STUB'
#!/bin/bash
echo identity-lookup >> "$HELPER_LOG"
echo '0 valid identities found'
STUB

    cat > "$barred_fixture/bin/spctl" <<'STUB'
#!/bin/bash
echo assess >> "$HELPER_LOG"
exit 1
STUB

    cat > "$barred_fixture/bin/xcrun" <<'STUB'
#!/bin/bash
echo 'Unexpected icon compilation or notarization' >&2
exit 33
STUB

    cat > "$barred_fixture/bin/ditto" <<'STUB'
#!/bin/bash
echo archive >> "$HELPER_LOG"
echo fixture > "${!#}"
STUB
    chmod +x "$barred_fixture/bin/"*
}

run_helper() {
    local identity="$1" keychain="$2" verification="$3"
    shift 3
    if env PATH="$barred_fixture/bin:/usr/bin:/bin" BASH_ENV=/dev/null \
        HELPER_LOG="$barred_fixture/calls" EXPECTED_KEYCHAIN="$keychain" \
        EXPECTED_IDENTITY="${identity:--}" VERIFY_STATUS="$verification" \
        CODESIGN_IDENTITY="$identity" KEYCHAIN_PATH="$keychain" \
        DEVELOPER_ID_APPLICATION='' APPLE_ID='' APPLE_ID_PASSWORD='' APPLE_TEAM_ID='' \
        "$@" \
        /bin/bash "$barred_fixture/Scripts/build-app.sh" > "$barred_fixture/output" 2>&1; then
        barred_status=0
    else
        barred_status=$?
    fi
}

assert_plist() {
    local key="$1" expected="$2" actual
    actual=$(/usr/libexec/PlistBuddy -c "Print :$key" "$barred_fixture/.build/Barred.app/Contents/Info.plist")
    [ "$actual" = "$expected" ] || fail "Expected $key=$expected; received $actual"
}

new_fixture
run_helper 'Fixture Identity' '' 0
[ "$barred_status" = 0 ] || fail 'Build helper failed with resolved metadata'
assert_plist CFBundleShortVersionString 4.5.6
assert_plist CFBundleVersion 78
assert_plist CFBundleName BuiltBarred
assert_plist LSMinimumSystemVersion 14.2
assert_plist DTSDKName macosx26.0

for overrides in both version build empty; do
    new_fixture
    case "$overrides" in
        both) run_helper 'Fixture Identity' '' 0 VERSION=8.9.10 BUILD_NUMBER=900 ;;
        version) run_helper 'Fixture Identity' '' 0 VERSION=8.9.10 ;;
        build) run_helper 'Fixture Identity' '' 0 BUILD_NUMBER=900 ;;
        empty) run_helper 'Fixture Identity' '' 0 VERSION='' BUILD_NUMBER='' ;;
    esac
    [ "$barred_status" = 0 ] || fail 'Build helper failed with packaging overrides'
    case "$overrides" in
        both|version) assert_plist CFBundleShortVersionString 8.9.10 ;;
        *) assert_plist CFBundleShortVersionString 4.5.6 ;;
    esac
    case "$overrides" in
        both|build) assert_plist CFBundleVersion 900 ;;
        *) assert_plist CFBundleVersion 78 ;;
    esac
    assert_plist CFBundleName BuiltBarred
    assert_plist LSMinimumSystemVersion 14.2
    assert_plist DTSDKName macosx26.0
done

for keychain in '' "$barred_test_temp/signing.keychain-db" \
    "$barred_test_temp/signing keys.keychain-db" "$barred_test_temp/signing[draft]*.keychain-db"; do
    new_fixture
    touch "$barred_test_temp/signingd-final.keychain-db"
    run_helper 'Fixture Identity' "$keychain" 0
    if [ "$barred_status" -ne 0 ]; then cat "$barred_fixture/output" >&2; fail 'Signed build helper failed'; fi
    [ "$(cat "$barred_fixture/calls")" = $'generate\nbuild\nsign\nsign\nverify\nassess\narchive' ] || fail 'Unexpected signed-build calls'
    [ -f "$barred_fixture/.build/Barred.zip" ] || fail 'Missing signed archive'
done

new_fixture
run_helper '' '' 0
[ "$barred_status" = 0 ] || fail 'Ad-hoc build helper failed'
[ "$(cat "$barred_fixture/calls")" = $'generate\nbuild\nidentity-lookup\nsign\narchive' ] || fail 'Unexpected ad-hoc calls'

new_fixture
run_helper 'Fixture Identity' "$barred_test_temp/signing keys.keychain-db" 42
[ "$barred_status" = 42 ] || fail 'Signature verification failure was not preserved'
[ "$(cat "$barred_fixture/calls")" = $'generate\nbuild\nsign\nsign\nverify' ] || fail 'Tools ran after signature verification failed'
[ ! -e "$barred_fixture/.build/Barred.zip" ] || fail 'Failed verification created an archive'

new_fixture
mkdir -p "$barred_fixture/.build/Barred.app"
echo previous > "$barred_fixture/.build/Barred.app/previous-artifact"
echo previous-zip > "$barred_fixture/.build/Barred.zip"
run_helper 'Fixture Identity' '' 0 OMIT_BUILT_PLIST=1
[ "$barred_status" -ne 0 ] || fail 'Missing built metadata was accepted'
[ -f "$barred_fixture/.build/Barred.app/previous-artifact" ] || fail 'Missing metadata removed the previous app'
[ "$(cat "$barred_fixture/.build/Barred.app/previous-artifact")" = previous ] || fail 'Missing metadata changed the previous app'
[ "$(cat "$barred_fixture/.build/Barred.zip")" = previous-zip ] || fail 'Missing metadata changed the previous archive'
[ "$(cat "$barred_fixture/calls")" = $'generate\nbuild' ] || fail 'Tools ran after missing metadata'

echo 'Passed 12 build-helper scenarios; no real builds, signing, or keychain access ran.'
