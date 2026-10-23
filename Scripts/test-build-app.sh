#!/bin/bash
# Exercise the build helper with isolated files and stubbed signing tools.
set -euo pipefail
unset VERSION BUILD_NUMBER

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/barred-build-helper.XXXXXX")
barred_test_temp=$(cd "$barred_test_temp" && pwd -P)
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
    cat > "$barred_fixture/bin/mv" <<'STUB'
#!/bin/bash
set -eu
args=("$@")
if [ "${1:-}" = -f ]; then shift; fi
case "${1##*/}:${2##*/}" in
    Barred.app:previous-Barred.app) phase=backup-app ;;
    Barred.zip:previous-Barred.zip) phase=backup-zip ;;
    previous-Barred.app:Barred.app) phase=restore-app ;;
    previous-Barred.zip:Barred.zip) phase=restore-zip ;;
    Barred.app:Barred.app) phase=promote-app ;;
    Barred.zip:Barred.zip) phase=promote-zip ;;
    *) phase=other ;;
esac
printf '%s\n' "$phase" >> "$MOVE_LOG"
if [ "${MOVE_FAILURE_PHASE:-}" = "$phase" ]; then exit "${MOVE_FAILURE_STATUS:-54}"; fi
case "$phase:${FAIL_RESTORE:-}" in
    restore-app:app|restore-app:both) exit 61 ;;
    restore-zip:zip|restore-zip:both) exit 62 ;;
esac
if [ "${MOVE_SIGNAL_AT:-}" = "before-$phase" ]; then
    kill -s "${MOVE_SIGNAL:-TERM}" "$PPID"
    exit 0
fi
/bin/mv "${args[@]}"
if [ "${MOVE_SIGNAL_AT:-}" = "after-$phase" ]; then kill -s "${MOVE_SIGNAL:-TERM}" "$PPID"; fi
STUB
    chmod +x "$barred_fixture/bin/"*
}

run_helper() {
    local identity="$1" keychain="$2" verification="$3"
    shift 3
    if env PATH="$barred_fixture/bin:/usr/bin:/bin" BASH_ENV=/dev/null \
        HELPER_LOG="$barred_fixture/calls" MOVE_LOG="$barred_fixture/moves" EXPECTED_KEYCHAIN="$keychain" \
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

snapshot_artifact() {
    local artifact=$1 path relative hash
    if [ -L "$artifact" ]; then printf 'link . %s\n' "$(readlink "$artifact")"; return; fi
    if [ ! -e "$artifact" ]; then printf 'missing\n'; return; fi
    while IFS= read -r path; do
        relative=${path#"$artifact"}
        relative=${relative:-.}
        if [ -L "$path" ]; then
            printf 'link %s %s\n' "$relative" "$(readlink "$path")"
        elif [ -d "$path" ]; then
            printf 'directory %s %s\n' "$relative" "$(stat -f '%Lp' "$path")"
        else
            hash=$(/usr/bin/shasum -a 256 "$path")
            printf 'file %s %s %s\n' "$relative" "$(stat -f '%Lp' "$path")" "${hash%% *}"
        fi
    done < <(find "$artifact" -print | LC_ALL=C sort)
}

promotion_fixture() {
    local shape=$1 name
    new_fixture
    mkdir -p "$barred_fixture/.build"
    if [ "$shape" = both ] || [ "$shape" = app ] || [ "$shape" = links ]; then
        mkdir -p "$barred_fixture/.build/Barred.app/Contents/Resources"
        printf 'Previous app' > "$barred_fixture/.build/Barred.app/previous-artifact"
        printf 'Previous resource' > "$barred_fixture/.build/Barred.app/Contents/Resources/payload"
        chmod 750 "$barred_fixture/.build/Barred.app"
        chmod 600 "$barred_fixture/.build/Barred.app/Contents/Resources/payload"
        ln -s payload "$barred_fixture/.build/Barred.app/Contents/Resources/resource link"
    fi
    if [ "$shape" = both ] || [ "$shape" = zip ] || [ "$shape" = links ]; then
        printf 'Previous ZIP bytes' > "$barred_fixture/.build/Barred.zip"
        chmod 640 "$barred_fixture/.build/Barred.zip"
    fi
    if [ "$shape" = links ]; then
        /bin/mv "$barred_fixture/.build/Barred.app" "$barred_fixture/.build/original-app"
        /bin/mv "$barred_fixture/.build/Barred.zip" "$barred_fixture/.build/original-zip"
        ln -s original-app "$barred_fixture/.build/Barred.app"
        ln -s original-zip "$barred_fixture/.build/Barred.zip"
    elif [ "$shape" = dangling ]; then
        ln -s missing-app "$barred_fixture/.build/Barred.app"
        ln -s missing-zip "$barred_fixture/.build/Barred.zip"
    fi
    printf 'Neighbor data' > "$barred_fixture/.build/neighbor"
    chmod 600 "$barred_fixture/.build/neighbor"
    for name in Barred.app Barred.zip neighbor original-app original-zip missing-app missing-zip; do
        snapshot_artifact "$barred_fixture/.build/$name" > "$barred_fixture/before-$name"
    done
}

assert_artifact() {
    local name=$1 path=${2:-$barred_fixture/.build/$1}
    snapshot_artifact "$path" > "$barred_fixture/after-$name"
    cmp -s "$barred_fixture/before-$name" "$barred_fixture/after-$name" || fail "Previous $name contents/modes/links were not restored"
}

assert_rollback() {
    local expected_status=$1 name
    [ "$barred_status" = "$expected_status" ] || fail "Promotion returned $barred_status instead of $expected_status"
    for name in Barred.app Barred.zip neighbor original-app original-zip missing-app missing-zip; do assert_artifact "$name"; done
    [ -z "$(find "$barred_fixture/.build" -maxdepth 1 -name '.barred-package.*' -print)" ] || fail 'Successful rollback left staging behind'
    ! grep -q 'Done! Outputs:' "$barred_fixture/output" || fail 'Failed promotion printed success'
}

barred_build_cases=26
for shape in both none app zip; do
    for phase in promote-app promote-zip; do
        promotion_fixture "$shape"
        if [ "$phase" = promote-app ]; then expected_status=54; else expected_status=55; fi
        run_helper 'Fixture Identity' '' 0 MOVE_FAILURE_PHASE="$phase" MOVE_FAILURE_STATUS="$expected_status"
        assert_rollback "$expected_status"
        barred_build_cases=$((barred_build_cases + 1))
    done
done
for phase in backup-app backup-zip; do
    promotion_fixture both
    run_helper 'Fixture Identity' '' 0 MOVE_FAILURE_PHASE="$phase" MOVE_FAILURE_STATUS=56
    assert_rollback 56
    barred_build_cases=$((barred_build_cases + 1))
done
for event in after-backup-app after-backup-zip before-promote-app before-promote-zip after-promote-app after-promote-zip; do
    promotion_fixture both
    run_helper 'Fixture Identity' '' 0 MOVE_SIGNAL_AT="$event" MOVE_SIGNAL=TERM
    assert_rollback 143
    barred_build_cases=$((barred_build_cases + 1))
done
for signal in INT HUP; do
    promotion_fixture both
    run_helper 'Fixture Identity' '' 0 MOVE_SIGNAL_AT=after-promote-app MOVE_SIGNAL="$signal"
    if [ "$signal" = INT ]; then expected_status=130; else expected_status=129; fi
    assert_rollback "$expected_status"
    barred_build_cases=$((barred_build_cases + 1))
done
promotion_fixture none
run_helper 'Fixture Identity' '' 0 MOVE_SIGNAL_AT=after-promote-app MOVE_SIGNAL=TERM
assert_rollback 143
barred_build_cases=$((barred_build_cases + 1))

for failure in app zip both; do
    promotion_fixture both
    run_helper 'Fixture Identity' '' 0 MOVE_FAILURE_PHASE=promote-zip MOVE_FAILURE_STATUS=55 FAIL_RESTORE="$failure"
    [ "$barred_status" = 55 ] || fail 'Rollback failure replaced the original status'
    staging=$(find "$barred_fixture/.build" -maxdepth 1 -type d -name '.barred-package.*' -print)
    [ -n "$staging" ] && [ -d "$staging" ] || fail 'Rollback failure lost recovery staging'
    grep -F "$staging" "$barred_fixture/output" >/dev/null || { cat "$barred_fixture/output" >&2; fail "Recovery path was not reported for $staging"; }
    grep -q '^restore-app$' "$barred_fixture/moves" || fail 'App restore was not attempted'
    grep -q '^restore-zip$' "$barred_fixture/moves" || fail 'ZIP restore was not attempted independently'
    if [ "$failure" = app ] || [ "$failure" = both ]; then
        assert_artifact Barred.app "$staging/previous-Barred.app"
    else
        assert_artifact Barred.app
    fi
    if [ "$failure" = zip ] || [ "$failure" = both ]; then
        assert_artifact Barred.zip "$staging/previous-Barred.zip"
    else
        assert_artifact Barred.zip
    fi
    assert_artifact neighbor
    ! grep -q 'Done! Outputs:' "$barred_fixture/output" || fail 'Rollback failure printed success'
    barred_build_cases=$((barred_build_cases + 1))
done
for shape in links dangling; do
    promotion_fixture "$shape"
    run_helper 'Fixture Identity' '' 0 MOVE_FAILURE_PHASE=promote-zip MOVE_FAILURE_STATUS=55
    assert_rollback 55
    barred_build_cases=$((barred_build_cases + 1))
done
promotion_fixture both
run_helper 'Fixture Identity' '' 0
[ "$barred_status" = 0 ] || fail 'Successful publication failed'
[ ! -e "$barred_fixture/.build/Barred.app/previous-artifact" ] || fail 'Successful publication retained obsolete content'
assert_artifact neighbor
[ -z "$(find "$barred_fixture/.build" -maxdepth 1 -name '.barred-package.*' -print)" ] || fail 'Success retained backups/staging'
barred_build_cases=$((barred_build_cases + 1))
echo "Passed $barred_build_cases build-helper scenarios; native tools were stubbed and promotion used disposable artifacts."
