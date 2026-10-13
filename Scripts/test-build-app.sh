#!/bin/bash
# Exercise the build helper with isolated files and stubbed signing tools.
set -euo pipefail

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
    if env PATH="$barred_fixture/bin:/usr/bin:/bin" BASH_ENV=/dev/null \
        HELPER_LOG="$barred_fixture/calls" EXPECTED_KEYCHAIN="$keychain" \
        EXPECTED_IDENTITY="${identity:--}" VERIFY_STATUS="$verification" \
        CODESIGN_IDENTITY="$identity" KEYCHAIN_PATH="$keychain" \
        DEVELOPER_ID_APPLICATION='' APPLE_ID='' APPLE_ID_PASSWORD='' APPLE_TEAM_ID='' \
        /bin/bash "$barred_fixture/Scripts/build-app.sh" > "$barred_fixture/output" 2>&1; then
        barred_status=0
    else
        barred_status=$?
    fi
}

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

echo 'Passed 6 build-helper scenarios; no real builds, signing, or keychain access ran.'
