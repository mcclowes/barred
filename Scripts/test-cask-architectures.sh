#!/bin/bash
set -euo pipefail

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/barred-cask-architectures.XXXXXX")
trap 'rm -rf "$barred_test_temp"' EXIT
mkdir -p "$barred_test_temp/bin" "$barred_test_temp/release app"
barred_test_binary="$barred_test_temp/release app/Barred [release]*"
touch "$barred_test_binary"

cat > "$barred_test_temp/bin/lipo" <<'STUB'
#!/bin/bash
set -eu
[ "$#" = 2 ] && [ "$1" = -archs ] && [ "$2" = "$EXPECTED_BINARY" ] || exit 31
[ "$INSPECTION_STATUS" = 0 ] || exit "$INSPECTION_STATUS"
printf '%s\n' "$BINARY_ARCHITECTURES"
STUB
chmod +x "$barred_test_temp/bin/lipo"

run_helper() {
    if env PATH="$barred_test_temp/bin:/usr/bin:/bin" BASH_ENV=/dev/null \
        EXPECTED_BINARY="$barred_test_binary" BINARY_ARCHITECTURES="$1" INSPECTION_STATUS="$2" \
        /bin/bash "$barred_test_source/Scripts/cask-architectures.sh" "$barred_test_binary" \
        > "$barred_test_temp/output" 2> "$barred_test_temp/error"; then
        barred_status=0
    else
        barred_status=$?
    fi
}

run_helper arm64 0
[ "$barred_status" = 0 ] || { cat "$barred_test_temp/error" >&2; exit 1; }
[ "$(cat "$barred_test_temp/output")" = ':arm64' ] || { echo 'Missing ARM64 cask requirement' >&2; exit 1; }

for architectures in x86_64 'arm64 x86_64' 'x86_64 arm64'; do
    run_helper "$architectures" 0
    [ "$barred_status" = 0 ] || { cat "$barred_test_temp/error" >&2; exit 1; }
    case "$architectures" in
        x86_64) expected=':x86_64' ;;
        'arm64 x86_64') expected=':arm64, :x86_64' ;;
        'x86_64 arm64') expected=':x86_64, :arm64' ;;
    esac
    [ "$(cat "$barred_test_temp/output")" = "$expected" ] || { echo 'Wrong cask architecture list' >&2; exit 1; }
done

for architectures in '' '   '; do
    run_helper "$architectures" 0
    [ "$barred_status" = 1 ] || { echo 'Empty architecture data was accepted' >&2; exit 1; }
    grep -q 'no supported architectures' "$barred_test_temp/error"
    [ ! -s "$barred_test_temp/output" ] || { echo 'Invalid data emitted cask metadata' >&2; exit 1; }
done

for architectures in ppc64 'arm64 ppc64' '*'; do
    run_helper "$architectures" 0
    [ "$barred_status" = 1 ] || { echo 'Unknown architecture data was accepted' >&2; exit 1; }
    grep -q 'Unsupported release architecture' "$barred_test_temp/error"
    [ ! -s "$barred_test_temp/output" ] || { echo 'Invalid data emitted cask metadata' >&2; exit 1; }
done

run_helper arm64 42
[ "$barred_status" = 42 ] || { echo 'Architecture inspection failure was not preserved' >&2; exit 1; }
[ ! -s "$barred_test_temp/output" ] || { echo 'Failed inspection emitted cask metadata' >&2; exit 1; }

for invocation in missing extra; do
    barred_arguments=()
    if [ "$invocation" = extra ]; then
        barred_arguments=("$barred_test_binary" extra)
    fi
    if /bin/bash "$barred_test_source/Scripts/cask-architectures.sh" ${barred_arguments[@]+"${barred_arguments[@]}"} \
        > "$barred_test_temp/output" 2> "$barred_test_temp/error"; then
        echo 'Invalid invocation was accepted' >&2
        exit 1
    else
        [ "$?" = 2 ] || { echo 'Invalid invocation did not report usage' >&2; exit 1; }
    fi
    grep -q 'Usage:' "$barred_test_temp/error"
    [ ! -s "$barred_test_temp/output" ] || { echo 'Invalid invocation emitted cask metadata' >&2; exit 1; }
done

echo 'Passed 12 cask architecture scenarios; no real builds, signing, or publishing ran.'
