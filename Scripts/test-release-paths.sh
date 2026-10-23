#!/bin/bash
# Check only the release workflow's settings lookups with fake Xcode.
set -euo pipefail

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/barred-release-paths.XXXXXX")
trap 'rm -rf "$barred_test_temp"' EXIT
mkdir "$barred_test_temp/bin"
ln -s /usr/bin/awk "$barred_test_temp/bin/awk"
ln -s /usr/bin/grep "$barred_test_temp/bin/grep"
cat > "$barred_test_temp/bin/xcodebuild" <<'STUB'
#!/bin/bash
set -eu
test "$#" -eq 7
test "$1" = -project
test "$2" = Barred.xcodeproj
test "$3" = -scheme
test "$4" = Barred
test "$5" = -configuration
test "$6" = Release
test "$7" = -showBuildSettings
printf '%s\n' "$BARRED_RELEASE_SETTINGS"
if [ "$BARRED_RELEASE_STATUS" != 0 ]; then echo 'Fixture Xcode failure' >&2; fi
exit "$BARRED_RELEASE_STATUS"
STUB
chmod +x "$barred_test_temp/bin/xcodebuild"

fail() { echo "$1" >&2; exit 1; }
lookup_prefix() {
    /usr/bin/awk -v step="$1" -v boundary="$2" '
      $0 == "      - name: " step { selected = 1; next }
      selected && /^      - name:/ { exit }
      selected && $0 == "        run: |" { body = 1; next }
      body {
        if ($0 ~ /^          /) line = substr($0, 11)
        else if ($0 ~ /^[[:space:]]*$/) line = ""
        else exit
        if (index(line, boundary) == 1) { found = 1; exit }
        print line
      }
      END { if (!found) exit 1 }
    ' "$barred_test_source/.github/workflows/release.yml"
}

barred_cases=0
for step in 'Notarize app' 'Find artifact'; do
    case "$step" in
        'Notarize app') boundary='APP_PATH=' ;;
        'Find artifact') boundary='cask_arches=' ;;
    esac
    lookup=$(lookup_prefix "$step" "$boundary") || fail "Cannot safely extract the lookup from $step"
    printf '%s\n' "$lookup" > "$barred_test_temp/lookup.sh"
    cat >> "$barred_test_temp/lookup.sh" <<'RESULT'
printf '%s\n' "$BUILD_DIR"
RESULT
    for scenario in ordinary spaced failed missing empty whitespace; do
        expected=''
        xcode_status=0
        expected_status=0
        case "$scenario" in
            ordinary|spaced)
                expected=/tmp/build-products/Release
                if [ "$scenario" = spaced ]; then expected='/tmp/build products [release]*.dir/Release'; fi
                settings=$(printf '    OTHER_BUILT_PRODUCTS_DIR = /wrong-prefix\n    BUILT_PRODUCTS_DIR = %s\n    BUILT_PRODUCTS_DIR = /later-target\n' "$expected")
                ;;
            failed)
                settings='    BUILT_PRODUCTS_DIR = /tmp/partial-output'
                xcode_status=42
                expected_status=42
                ;;
            missing)
                settings='    OTHER_BUILT_PRODUCTS_DIR = /wrong-prefix'
                expected_status=1
                ;;
            empty)
                settings=$'    BUILT_PRODUCTS_DIR =\n    BUILT_PRODUCTS_DIR = /later-target'
                expected_status=1
                ;;
            whitespace)
                settings=$'    BUILT_PRODUCTS_DIR = \t \n    BUILT_PRODUCTS_DIR = /later-target'
                expected_status=1
                ;;
        esac
        # Only the fake Xcode and read-only lookup utilities are available to extracted code.
        if env -u SHELLOPTS -u BASHOPTS PATH="$barred_test_temp/bin" BASH_ENV=/dev/null \
            BARRED_RELEASE_SETTINGS="$settings" BARRED_RELEASE_STATUS="$xcode_status" \
            /bin/bash -e "$barred_test_temp/lookup.sh" \
            > "$barred_test_temp/output" 2> "$barred_test_temp/error"; then
            result=0
        else
            result=$?
        fi
        [ "$result" = "$expected_status" ] || fail "$step/$scenario returned $result instead of $expected_status"
        if [ "$expected_status" = 0 ]; then
            printf '%s\n' "$expected" > "$barred_test_temp/expected"
            cmp -s "$barred_test_temp/output" "$barred_test_temp/expected" || fail "$step/$scenario lost the complete first exact directory: $(cat "$barred_test_temp/output")"
        else
            [ ! -s "$barred_test_temp/output" ] || fail "$step/$scenario accepted unusable settings"
            if [ "$scenario" = failed ]; then
                grep -q 'Fixture Xcode failure' "$barred_test_temp/error" || fail 'Xcode failure diagnostic was hidden'
            else
                grep -q 'build products directory' "$barred_test_temp/error" || fail 'Missing directory diagnostic'
            fi
        fi
        barred_cases=$((barred_cases + 1))
    done
done
echo "Passed $barred_cases release-path scenarios; only lookup prefixes ran with fake Xcode."
