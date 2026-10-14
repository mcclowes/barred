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
exit "${GENERATE_STATUS:-0}"
STUB

    cat > "$barred_fixture/bin/xcodebuild" <<'STUB'
#!/bin/bash
set -eu
echo build >> "$HELPER_LOG"
if [ "${BUILD_STATUS:-0}" -ne 0 ]; then exit "$BUILD_STATUS"; fi
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
exit "${SIGN_STATUS:-0}"
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
set -eu
case "$1" in
    actool)
        echo icon >> "$HELPER_LOG"
        shift
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --compile) output="$2"; shift ;;
                --output-partial-info-plist) info="$2"; shift ;;
            esac
            shift
        done
        echo fixture-icon > "$output/barred.icns"
        echo fixture-info > "$info"
        exit "${ICON_STATUS:-0}"
        ;;
    notarytool)
        echo notary >> "$HELPER_LOG"
        exit "${NOTARY_STATUS:-0}"
        ;;
    stapler)
        echo staple >> "$HELPER_LOG"
        echo fixture-ticket > "$3/Contents/ticket"
        exit "${STAPLE_STATUS:-0}"
        ;;
esac
exit 33
STUB

    cat > "$barred_fixture/bin/ditto" <<'STUB'
#!/bin/bash
set -eu
echo archive >> "$HELPER_LOG"
if [ "${ARCHIVE_STATUS:-0}" -ne 0 ] || \
    { [ "${REZIP_STATUS:-0}" -ne 0 ] && [ "$(grep -c '^archive$' "$HELPER_LOG")" -eq 2 ]; }; then
    echo partial > "${!#}"
    exit "${ARCHIVE_STATUS:-${REZIP_STATUS:-73}}"
fi
if [ "${CORRUPT_ARCHIVE:-0}" = 1 ]; then
    echo partial > "${!#}"
    exit 0
fi
exec /usr/bin/ditto "$@"
STUB
    cat > "$barred_fixture/bin/cp" <<'STUB'
#!/bin/bash
if [ "${COPY_STATUS:-0}" -ne 0 ]; then exit "$COPY_STATUS"; fi
exec /bin/cp "$@"
STUB
    cat > "$barred_fixture/bin/shasum" <<'STUB'
#!/bin/bash
if [ "${HASH_STATUS:-0}" -ne 0 ]; then
    echo partial-hash
    exit "$HASH_STATUS"
fi
exec /usr/bin/shasum "$@"
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

new_fixture
mkdir -p "$barred_fixture/.build/Barred.app"
echo previous > "$barred_fixture/.build/Barred.app/previous-artifact"
echo previous-zip > "$barred_fixture/.build/Barred.zip"
run_helper 'Fixture Identity' '' 0 SIGN_STATUS=43
[ "$barred_status" = 43 ] || fail 'Signing failure was not preserved'
[ -f "$barred_fixture/.build/Barred.app/previous-artifact" ] || fail 'Signing failure removed the previous app'
[ "$(cat "$barred_fixture/.build/Barred.app/previous-artifact")" = previous ] || fail 'Signing failure changed the previous app'
[ "$(cat "$barred_fixture/.build/Barred.zip")" = previous-zip ] || fail 'Signing failure changed the previous ZIP'
assert_preserved() {
    [ "$(cat "$barred_fixture/.build/Barred.app/previous-artifact")" = previous ] || fail 'Preparation failure changed the previous app'
    [ "$(cat "$barred_fixture/.build/Barred.zip")" = previous-zip ] || fail 'Preparation failure changed the previous ZIP'
    [ -z "$(find "$barred_fixture/.build" -name '.barred-package.*' -print)" ] || fail 'Preparation left staging behind'
    if grep -q 'Done! Outputs:' "$barred_fixture/output"; then fail 'Preparation failure printed success'; fi
}

for failure in generate build copy icon verify archive corrupt hash notary staple rezip; do
    new_fixture
    mkdir -p "$barred_fixture/.build/Barred.app" "$barred_fixture/barred.icon"
    echo previous > "$barred_fixture/.build/Barred.app/previous-artifact"
    echo previous-zip > "$barred_fixture/.build/Barred.zip"
    case "$failure" in
        generate) run_helper 'Fixture Identity' '' 0 GENERATE_STATUS=41 ;;
        build) run_helper 'Fixture Identity' '' 0 BUILD_STATUS=42 ;;
        copy) run_helper 'Fixture Identity' '' 0 COPY_STATUS=44 ;;
        icon) run_helper 'Fixture Identity' '' 0 ICON_STATUS=45 ;;
        verify) run_helper 'Fixture Identity' '' 46 ;;
        archive) run_helper 'Fixture Identity' '' 0 ARCHIVE_STATUS=47 ;;
        corrupt) run_helper 'Fixture Identity' '' 0 CORRUPT_ARCHIVE=1 ;;
        hash) run_helper 'Fixture Identity' '' 0 HASH_STATUS=48 ;;
        notary|staple|rezip)
            case "$failure" in
                notary) failure_setting=NOTARY_STATUS=49 ;;
                staple) failure_setting=STAPLE_STATUS=50 ;;
                rezip) failure_setting=REZIP_STATUS=51 ;;
            esac
            run_helper 'Fixture Identity' '' 0 DEVELOPER_ID_APPLICATION='Fixture Identity' \
                APPLE_ID=fixture@example.invalid APPLE_ID_PASSWORD=fixture-password \
                APPLE_TEAM_ID=FIXTURETEAM "$failure_setting"
            ;;
    esac
    [ "$barred_status" -ne 0 ] || fail "Preparation accepted failure: $failure"
    assert_preserved
done

new_fixture
mkdir -p "$barred_fixture/.build/Barred.app" "$barred_fixture/barred.icon"
echo obsolete > "$barred_fixture/.build/Barred.app/removed-resource"
echo previous-zip > "$barred_fixture/.build/Barred.zip"
run_helper 'Fixture Identity' '' 0 DEVELOPER_ID_APPLICATION='Fixture Identity' \
    APPLE_ID=fixture@example.invalid APPLE_ID_PASSWORD=fixture-password APPLE_TEAM_ID=FIXTURETEAM
[ "$barred_status" = 0 ] || { cat "$barred_fixture/output" >&2; fail 'Staged notarization fixture failed'; }
[ ! -e "$barred_fixture/.build/Barred.app/removed-resource" ] || fail 'Successful replacement kept obsolete app content'
[ "$(unzip -p "$barred_fixture/.build/Barred.zip" Barred.app/Contents/ticket)" = fixture-ticket ] || fail 'Final ZIP omitted stapled fixture ticket'
[ "$(grep -c '^archive$' "$barred_fixture/calls")" = 2 ] || fail 'Notarization did not rebuild the final ZIP'
[ -z "$(find "$barred_fixture/.build" -name '.barred-package.*' -print)" ] || fail 'Success left staging behind'
expected_hash=$(/usr/bin/shasum -a 256 "$barred_fixture/.build/Barred.zip")
grep -Fx "SHA256: ${expected_hash%% *}" "$barred_fixture/output"

new_fixture
mkdir -p "$barred_fixture/.build/Barred.zip" "$barred_fixture/.build/Barred.app"
echo previous > "$barred_fixture/.build/Barred.app/previous-artifact"
echo preserve-directory > "$barred_fixture/.build/Barred.zip/sentinel"
run_helper 'Fixture Identity' '' 0
[ "$barred_status" -ne 0 ] || fail 'ZIP directory destination was accepted'
[ "$(cat "$barred_fixture/.build/Barred.zip/sentinel")" = preserve-directory ] || fail 'ZIP directory destination changed'
[ "$(cat "$barred_fixture/.build/Barred.app/previous-artifact")" = previous ] || fail 'ZIP directory rejection changed the previous app'
echo 'Passed 26 build-helper scenarios; no real builds, signing, notarization, or keychain access ran.'
