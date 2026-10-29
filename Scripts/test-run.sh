#!/usr/bin/env bash
set -euo pipefail
unset MAKEFLAGS MFLAGS MAKEOVERRIDES MAKELEVEL MAKEFILES PROJECT SCHEME DEV_CODE_SIGN_IDENTITY DEV_DEVELOPMENT_TEAM BASH_ENV ENV

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_make=${BARRED_TEST_MAKE:-/usr/bin/make}
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
export PATH="$barred_test_temp/bin:/usr/bin:/bin"
export LC_ALL=C

"$barred_test_make" -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1 || { cat "$barred_test_temp/run.log" >&2; exit 1; }
if [ "$(cat "$BARRED_RUN_TEST_LAUNCH")" != "$BARRED_RUN_TEST_OUTPUT/Barred.app" ]; then
    echo 'make run did not pass the complete app path to open.' >&2
    cat "$BARRED_RUN_TEST_LAUNCH" >&2
    exit 1
fi
export BARRED_RUN_TEST_OUTPUT="$barred_test_temp/products"
"$barred_test_make" -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1
test "$(cat "$BARRED_RUN_TEST_LAUNCH")" = "$BARRED_RUN_TEST_OUTPUT/Barred.app"
rm "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=missing-directory
if "$barred_test_make" -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1; then
    echo 'make run succeeded without a product directory.' >&2
    exit 1
fi
test ! -e "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=settings-failure
if "$barred_test_make" -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1; then
    echo 'make run succeeded after a failed build-settings lookup.' >&2
    exit 1
fi
test ! -e "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=build-failure
if "$barred_test_make" -s -C "$barred_test_project" run > "$barred_test_temp/run.log" 2>&1; then
    echo 'make run succeeded after a failed build.' >&2
    exit 1
fi
test ! -e "$BARRED_RUN_TEST_LAUNCH"
export BARRED_RUN_TEST_MODE=''
export BARRED_RUN_TEST_PROJECT='Custom Project.xcodeproj'
export BARRED_RUN_TEST_SCHEME='Custom Scheme'
if ! "$barred_test_make" -s -C "$barred_test_project" run "PROJECT=$BARRED_RUN_TEST_PROJECT" \
    "SCHEME=$BARRED_RUN_TEST_SCHEME" > "$barred_test_temp/run.log" 2>&1; then
    cat "$barred_test_temp/run.log" >&2
    exit 1
fi
test "$(cat "$BARRED_RUN_TEST_LAUNCH")" = "$BARRED_RUN_TEST_OUTPUT/Barred.app"
export BARRED_RUN_TEST_IDENTITY='Apple Development: Fixture Identity (TESTTEAM)'
export BARRED_RUN_TEST_TEAM=TESTTEAM
"$barred_test_make" -s -C "$barred_test_project" run "PROJECT=$BARRED_RUN_TEST_PROJECT" \
    "SCHEME=$BARRED_RUN_TEST_SCHEME" "DEV_CODE_SIGN_IDENTITY=$BARRED_RUN_TEST_IDENTITY" \
    "DEV_DEVELOPMENT_TEAM=$BARRED_RUN_TEST_TEAM" > "$barred_test_temp/run.log" 2>&1 || \
    { cat "$barred_test_temp/run.log" >&2; exit 1; }
test "$(cat "$BARRED_RUN_TEST_LAUNCH")" = "$BARRED_RUN_TEST_OUTPUT/Barred.app"

export BARRED_RUN_TEST_ARGUMENTS="$barred_test_temp/xcode-arguments"
cat > "$barred_test_temp/bin/xcodebuild" <<'STUB'
#!/usr/bin/env bash
set -eu
printf '<%s>' "$@" >> "$BARRED_RUN_TEST_ARGUMENTS"
printf '\n' >> "$BARRED_RUN_TEST_ARGUMENTS"
if [ -n "$BARRED_RUN_TEST_CONFIGURATION" ]; then
    test "$#" -eq 7
    test "$5" = -configuration
    test "$6" = "$BARRED_RUN_TEST_CONFIGURATION"
    action=$7
else
    test "$#" -eq 5
    action=$5
fi
test "$1" = -project
test "$2" = "$BARRED_RUN_TEST_PROJECT"
test "$3" = -scheme
test "$4" = "$BARRED_RUN_TEST_SCHEME"
test "$action" = "$BARRED_RUN_TEST_ACTION"
if [ "$BARRED_RUN_TEST_MODE" = xcode-failure ]; then
    exit 41
fi
STUB
chmod +x "$barred_test_temp/bin/xcodebuild"

fail() { echo "$1" >&2; exit 1; }
barred_make_cases=0
for target in build release test clean; do
    for variant in default custom failure; do
        export BARRED_RUN_TEST_MODE=''
        export BARRED_RUN_TEST_PROJECT=Barred.xcodeproj
        barred_make_scheme=Barred
        if [ "$variant" != default ]; then
            export BARRED_RUN_TEST_PROJECT='Custom Project.xcodeproj'
            barred_make_scheme='Custom Scheme'
        fi
        export BARRED_RUN_TEST_SCHEME="$barred_make_scheme"
        export BARRED_RUN_TEST_CONFIGURATION=Debug
        export BARRED_RUN_TEST_ACTION=build
        case "$target" in
            release) export BARRED_RUN_TEST_CONFIGURATION=Release ;;
            test) export BARRED_RUN_TEST_ACTION=test BARRED_RUN_TEST_SCHEME=BarredTests ;;
            clean) export BARRED_RUN_TEST_ACTION=clean BARRED_RUN_TEST_CONFIGURATION='' ;;
        esac
        if [ "$variant" = failure ]; then export BARRED_RUN_TEST_MODE=xcode-failure; fi
        args=("$target")
        if [ "$variant" != default ]; then
            args+=("PROJECT=$BARRED_RUN_TEST_PROJECT" "SCHEME=$barred_make_scheme")
        fi
        expected=(-project "$BARRED_RUN_TEST_PROJECT" -scheme "$BARRED_RUN_TEST_SCHEME")
        if [ -n "$BARRED_RUN_TEST_CONFIGURATION" ]; then
            expected+=(-configuration "$BARRED_RUN_TEST_CONFIGURATION")
        fi
        expected+=("$BARRED_RUN_TEST_ACTION")
        printf '<%s>' "${expected[@]}" > "$barred_test_temp/expected-arguments"
        printf '\n' >> "$barred_test_temp/expected-arguments"
        : > "$BARRED_RUN_TEST_ARGUMENTS"
        rm -f "$BARRED_RUN_TEST_LAUNCH"
        mkdir -p "$barred_test_project/.build/Barred.app"
        printf 'Previous app' > "$barred_test_project/.build/Barred.app/sentinel"
        printf 'Previous zip' > "$barred_test_project/.build/Barred.zip"
        printf 'Unrelated output' > "$barred_test_project/.build/keep.txt"
        if "$barred_test_make" -s -C "$barred_test_project" "${args[@]}" > "$barred_test_temp/run.log" 2>&1; then
            result=0
        else
            result=$?
        fi
        cmp -s "$BARRED_RUN_TEST_ARGUMENTS" "$barred_test_temp/expected-arguments" || \
            fail "Wrong Xcode arguments for $target/$variant: $(cat "$BARRED_RUN_TEST_ARGUMENTS")"
        if [ "$variant" = failure ]; then
            [ "$result" != 0 ] || fail "$target ignored an Xcode failure"
            grep -q 'Error 41' "$barred_test_temp/run.log" || fail "$target lost the Xcode failure status"
        else
            [ "$result" = 0 ] || fail "$target/$variant failed: $(cat "$barred_test_temp/run.log")"
        fi
        [ ! -e "$BARRED_RUN_TEST_LAUNCH" ] || fail "$target requested app launch"
        if [ "$target" = clean ] && [ "$variant" != failure ]; then
            [ ! -e "$barred_test_project/.build/Barred.app" ] || fail 'Clean retained the fixture app'
            [ ! -e "$barred_test_project/.build/Barred.zip" ] || fail 'Clean retained the fixture archive'
        else
            [ "$(cat "$barred_test_project/.build/Barred.app/sentinel")" = 'Previous app' ] || fail 'Changed prior fixture app'
            [ "$(cat "$barred_test_project/.build/Barred.zip")" = 'Previous zip' ] || fail 'Changed prior fixture archive'
        fi
        [ "$(cat "$barred_test_project/.build/keep.txt")" = 'Unrelated output' ] || fail 'Changed unrelated output'
        barred_make_cases=$((barred_make_cases + 1))
    done
done
test "$barred_make_cases" -eq 12
echo "Passed $((7 + barred_make_cases)) Make/launch scenarios; Xcode/open were stubbed and cleanup used disposable outputs only."
