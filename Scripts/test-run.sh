#!/usr/bin/env bash
set -euo pipefail
unset MAKEFLAGS MFLAGS MAKEOVERRIDES DEV_CODE_SIGN_IDENTITY DEV_DEVELOPMENT_TEAM

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/barred-run.XXXXXX")
trap 'rm -rf "$barred_test_temp"' EXIT
barred_test_project="$barred_test_temp/project with spaces"
export BARRED_RUN_TEST_OUTPUT="$barred_test_temp/build products"
export BARRED_RUN_TEST_LAUNCH="$barred_test_temp/launch"
export BARRED_RUN_TEST_MODE=''
export BARRED_RUN_TEST_PROJECT=Barred.xcodeproj
export BARRED_RUN_TEST_SCHEME=Barred
export BARRED_RUN_TEST_IDENTITY="Apple Development"
export BARRED_RUN_TEST_TEAM=BCB43KG62T
mkdir -p "$barred_test_project" "$barred_test_temp/bin"
cp "$barred_test_source/Makefile" "$barred_test_project/Makefile"

cat > "$barred_test_temp/bin/xcodebuild" <<'STUB'
#!/usr/bin/env bash
set -eu
test "$1" = -project
test "$2" = "$BARRED_RUN_TEST_PROJECT"
test "$3" = -scheme
test "$4" = "$BARRED_RUN_TEST_SCHEME"
test "$5" = -configuration
test "$6" = Debug
for argument in "$@"; do
    if [ "$argument" = -showBuildSettings ]; then
        test "$#" -eq 7
        if [ "$BARRED_RUN_TEST_MODE" = missing-directory ]; then
            printf '    PRODUCT_NAME = Barred\n'
            exit 0
        fi
        if [ "$BARRED_RUN_TEST_MODE" = settings-failure ]; then
            printf '    BUILT_PRODUCTS_DIR = %s\n' "$BARRED_RUN_TEST_OUTPUT"
            exit 42
        fi
        printf '    OTHER_BUILT_PRODUCTS_DIR = /wrong-prefix\n'
        printf '    BUILT_PRODUCTS_DIR = %s\n' "$BARRED_RUN_TEST_OUTPUT"
        printf '    BUILT_PRODUCTS_DIR = /later-target\n'
        exit 0
    fi
done
test "$#" -eq 10 || { echo 'Expected development signing arguments for launch build' >&2; exit 32; }
test "$7" = "CODE_SIGN_IDENTITY=$BARRED_RUN_TEST_IDENTITY"
test "$8" = "DEVELOPMENT_TEAM=$BARRED_RUN_TEST_TEAM"
test "$9" = CODE_SIGN_STYLE=Manual
test "${10}" = build
if [ "$BARRED_RUN_TEST_MODE" = build-failure ]; then
    exit 41
fi
STUB
cat > "$barred_test_temp/bin/open" <<'STUB'
#!/usr/bin/env bash
set -eu
test "$#" -eq 1
printf '%s\n' "$1" > "$BARRED_RUN_TEST_LAUNCH"
STUB
chmod +x "$barred_test_temp/bin/xcodebuild" "$barred_test_temp/bin/open"
export PATH="$barred_test_temp/bin:$PATH"

make -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1 || { cat "$barred_test_temp/run.log" >&2; exit 1; }
if [ "$(cat "$BARRED_RUN_TEST_LAUNCH")" != "$BARRED_RUN_TEST_OUTPUT/Barred.app" ]; then
    echo 'make run did not pass the complete app path to open.' >&2
    cat "$BARRED_RUN_TEST_LAUNCH" >&2
    exit 1
fi
export BARRED_RUN_TEST_OUTPUT="$barred_test_temp/products"
make -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1
test "$(cat "$BARRED_RUN_TEST_LAUNCH")" = "$BARRED_RUN_TEST_OUTPUT/Barred.app"
rm "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=missing-directory
if make -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1; then
    echo 'make run succeeded without a product directory.' >&2
    exit 1
fi
test ! -e "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=settings-failure
if make -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1; then
    echo 'make run succeeded after a failed build-settings lookup.' >&2
    exit 1
fi
test ! -e "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=build-failure
if make -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1; then
    echo 'make run succeeded after a failed build.' >&2
    exit 1
fi
test ! -e "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=''
export BARRED_RUN_TEST_PROJECT='Custom Project.xcodeproj'
export BARRED_RUN_TEST_SCHEME='Custom Scheme'
if ! make -s -C "$barred_test_project" run "PROJECT=$BARRED_RUN_TEST_PROJECT" \
    "SCHEME=$BARRED_RUN_TEST_SCHEME" > "$barred_test_temp/run.log" 2>&1; then
    cat "$barred_test_temp/run.log" >&2
    exit 1
fi
test "$(cat "$BARRED_RUN_TEST_LAUNCH")" = "$BARRED_RUN_TEST_OUTPUT/Barred.app"
export BARRED_RUN_TEST_IDENTITY='Apple Development: Fixture Identity (TESTTEAM)'
export BARRED_RUN_TEST_TEAM=TESTTEAM
make -s -C "$barred_test_project" run "PROJECT=$BARRED_RUN_TEST_PROJECT" \
    "SCHEME=$BARRED_RUN_TEST_SCHEME" "DEV_CODE_SIGN_IDENTITY=$BARRED_RUN_TEST_IDENTITY" \
    "DEV_DEVELOPMENT_TEAM=$BARRED_RUN_TEST_TEAM" > "$barred_test_temp/run.log" 2>&1 || \
    { cat "$barred_test_temp/run.log" >&2; exit 1; }
test "$(cat "$BARRED_RUN_TEST_LAUNCH")" = "$BARRED_RUN_TEST_OUTPUT/Barred.app"
echo 'Passed 7 launch helper scenarios; signing arguments, builds, and app launch used fixtures.'
