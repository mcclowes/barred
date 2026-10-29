#!/bin/bash
set -euo pipefail
unset MAKEFLAGS MFLAGS MAKEOVERRIDES MAKEFILES GNUMAKEFLAGS TYPE PUSH BARRED_BUMP_TYPE BARRED_BUMP_PUSH

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/barred-bump-version.XXXXXX")
trap 'rm -rf "$barred_test_temp"' EXIT
barred_cases=0

fail() { echo "$1" >&2; exit 1; }

new_fixture() {
    barred_fixture=$(mktemp -d "$barred_test_temp/project with spaces.XXXXXX")
    mkdir -p "$barred_fixture/bin"
    cat > "$barred_fixture/project.yml" <<'PROJECT'
settings:
  MARKETING_VERSION: "4.5.6"
  CURRENT_PROJECT_VERSION: 78
  SENTINEL: unchanged
PROJECT
    cp "$barred_fixture/project.yml" "$barred_fixture/original.yml"
    cat > "$barred_fixture/bin/git" <<'STUB'
#!/bin/bash
printf '<%s>' "$@" >> "$GIT_LOG"
printf '\n' >> "$GIT_LOG"
exit "${GIT_STATUS:-97}"
STUB
    chmod +x "$barred_fixture/bin/git"
}

run_helper() {
    if (cd "$barred_fixture" && env PATH="$barred_fixture/bin:/usr/bin:/bin" \
        BASH_ENV=/dev/null GIT_LOG="$barred_fixture/git.log" GIT_STATUS="${barred_git_status:-97}" \
        /bin/bash "$barred_test_source/Scripts/bump-version.sh" "$@") \
        > "$barred_fixture/output" 2> "$barred_fixture/error"; then
        barred_status=0
    else
        barred_status=$?
    fi
}

assert_bump() {
    local expected_version=$1 mode=$2
    [ "$barred_status" = 0 ] || fail "Valid $mode bump failed: $(cat "$barred_fixture/error")"
    cat > "$barred_fixture/expected.yml" <<PROJECT
settings:
  MARKETING_VERSION: "$expected_version"
  CURRENT_PROJECT_VERSION: 78
  SENTINEL: unchanged
PROJECT
    cmp -s "$barred_fixture/project.yml" "$barred_fixture/expected.yml" || fail 'Wrong version metadata'
    cat > "$barred_fixture/expected-git.log" <<GIT
<add><project.yml>
<commit><-m><Bump version to $expected_version>
<tag><-a><v$expected_version><-m><Release v$expected_version>
GIT
    if [ "$mode" = push ]; then
        cat >> "$barred_fixture/expected-git.log" <<GIT
<push><origin><HEAD>
<push><origin><v$expected_version>
GIT
    fi
    cmp -s "$barred_fixture/git.log" "$barred_fixture/expected-git.log" || fail "Wrong Git actions for $mode bump"
    [ ! -s "$barred_fixture/error" ] || fail 'Valid bump emitted errors'
}

reject_arguments() {
    new_fixture
    run_helper "$@"
    [ "$barred_status" = 2 ] || fail "Invalid arguments returned $barred_status instead of usage status 2: $*"
    grep -q 'Usage:' "$barred_fixture/error" || fail 'Missing usage diagnostic on stderr'
    [ ! -s "$barred_fixture/output" ] || fail 'Invalid arguments emitted release progress'
    cmp -s "$barred_fixture/project.yml" "$barred_fixture/original.yml" || fail 'Invalid arguments changed project metadata'
    [ ! -e "$barred_fixture/git.log" ] || fail 'Invalid arguments invoked Git'
    barred_cases=$((barred_cases + 1))
}

reject_arguments patch --pus
reject_arguments patch --push extra
reject_arguments
reject_arguments ''
reject_arguments release
reject_arguments PATCH
reject_arguments --push
reject_arguments patch ''
reject_arguments minor --help
reject_arguments major extra
reject_arguments patch --push --push
reject_arguments patch extra ignored

new_fixture
mv "$barred_fixture/project.yml" "$barred_fixture/unread-project.yml"
run_helper patch --pus
[ "$barred_status" = 2 ] || fail 'Invalid arguments tried to read missing project metadata'
grep -q 'Usage:' "$barred_fixture/error" || fail 'Missing usage before project read'
[ ! -e "$barred_fixture/git.log" ] || fail 'Invalid arguments invoked Git without project metadata'
barred_cases=$((barred_cases + 1))

barred_git_status=0
for bump in major minor patch; do
    case "$bump" in
        major) expected_version=5.0.0 ;;
        minor) expected_version=4.6.0 ;;
        patch) expected_version=4.5.7 ;;
    esac
    for mode in local push; do
        new_fixture
        if [ "$mode" = push ]; then
            run_helper "$bump" --push
        else
            run_helper "$bump"
        fi
        assert_bump "$expected_version" "$mode"
        barred_cases=$((barred_cases + 1))
    done
done

barred_real_make=${BARRED_TEST_MAKE:-/usr/bin/make}

new_make_fixture() {
    new_fixture
    mkdir "$barred_fixture/Scripts"
    cp "$barred_test_source/Scripts/bump-version.sh" "$barred_fixture/Scripts/"
    cp "$barred_test_source/Makefile" "$barred_fixture/"
    touch "$barred_fixture/patch" "$barred_fixture/--push"
}

run_make() {
    if (cd "$barred_fixture" && env PATH="$barred_fixture/bin:/usr/bin:/bin" \
        BASH_ENV=/dev/null GIT_LOG="$barred_fixture/git.log" GIT_STATUS=0 \
        "$barred_real_make" --no-print-directory -s bump "$@") \
        > "$barred_fixture/output" 2> "$barred_fixture/error"; then
        barred_status=0
    else
        barred_status=$?
    fi
}

reject_make_arguments() {
    new_make_fixture
    run_make "$@"
    [ "$barred_status" = 2 ] || fail "Make accepted malformed arguments: $*; Git requests: $(cat "$barred_fixture/git.log" 2>/dev/null || true)"
    grep -q 'Usage:' "$barred_fixture/error" || fail 'Make did not reach helper argument validation'
    [ ! -s "$barred_fixture/output" ] || fail 'Malformed Make input emitted release progress'
    cmp -s "$barred_fixture/project.yml" "$barred_fixture/original.yml" || fail 'Malformed Make input changed metadata'
    [ ! -e "$barred_fixture/git.log" ] || fail 'Malformed Make input invoked Git'
    [ ! -e "$barred_fixture/make-marker" ] || fail 'Make evaluated literal shell punctuation'
    barred_cases=$((barred_cases + 1))
}

for value in 'patch --push' 'patch ' 'patc?' '"patch"' \
    'patch; touch make-marker' "patch\$\$(touch make-marker)" \
    "patch\`touch make-marker\`" 'patch > make-marker' 'patch && touch make-marker'; do
    reject_make_arguments "TYPE=$value"
done
reject_make_arguments
reject_make_arguments 'TYPE='
reject_make_arguments PUSH=--push
for value in --pus '--push extra' '--push ' '--pus?' \
    '--push; touch make-marker' "--push\$\$(touch make-marker)" \
    "--push\`touch make-marker\`" '--push > make-marker'; do
    reject_make_arguments TYPE=patch "PUSH=$value"
done
reject_make_arguments 'TYPE=patch --push' PUSH=--push

for bump in major minor patch; do
    case "$bump" in
        major) expected_version=5.0.0 ;;
        minor) expected_version=4.6.0 ;;
        patch) expected_version=4.5.7 ;;
    esac
    for mode in local empty push; do
        new_make_fixture
        case "$mode" in
            local) run_make "TYPE=$bump" ;;
            empty) run_make "TYPE=$bump" PUSH= ;;
            push) run_make "TYPE=$bump" PUSH=--push ;;
        esac
        assert_bump "$expected_version" "$mode"
        barred_cases=$((barred_cases + 1))
    done
done
new_make_fixture
run_make 'TYPE= patch' 'PUSH= '
assert_bump 4.5.7 local
barred_cases=$((barred_cases + 1))
new_make_fixture
run_make 'TYPE= minor' 'PUSH= --push'
assert_bump 4.6.0 push
barred_cases=$((barred_cases + 1))

echo "Passed $barred_cases version-helper scenarios; no real Git mutations ran."
