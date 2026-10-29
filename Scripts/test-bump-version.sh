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
<--no-optional-locks><status><--porcelain=v1><--untracked-files=all>
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

barred_real_git=$(command -v git)
mkdir -p "$barred_test_temp/home" "$barred_test_temp/tmp"

metadata_env() {
    env -i PATH=/usr/bin:/bin HOME="$barred_test_temp/home" TMPDIR="$barred_test_temp/tmp" \
        BASH_ENV=/dev/null LC_ALL=C \
        GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_COUNT=3 \
        GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
        GIT_CONFIG_KEY_1=commit.gpgSign GIT_CONFIG_VALUE_1=false \
        GIT_CONFIG_KEY_2=tag.gpgSign GIT_CONFIG_VALUE_2=false \
        GIT_AUTHOR_NAME=Fixture GIT_AUTHOR_EMAIL=fixture@example.com \
        GIT_COMMITTER_NAME=Fixture GIT_COMMITTER_EMAIL=fixture@example.com "$@"
}

metadata_git() { metadata_env "$barred_real_git" -C "$barred_metadata_repo" "$@"; }

assert_status_only() {
    printf '%s\n' '<--no-optional-locks><status><--porcelain=v1><--untracked-files=all>' > "$barred_metadata_dir/expected-status.log"
    cmp -s "$barred_metadata_dir/git.log" "$barred_metadata_dir/expected-status.log" || fail 'Rejected input reached Git beyond read-only status'
}

metadata_document() {
    printf 'settings:\n  MARKETING_VERSION: "%s"\n  CURRENT_PROJECT_VERSION: 78\n  SENTINEL: unchanged\n' "$1"
}

metadata_fixture() {
    barred_metadata_dir=$(mktemp -d "$barred_test_temp/metadata project.XXXXXX")
    barred_metadata_repo="$barred_metadata_dir/repo"
    mkdir -p "$barred_metadata_repo/Scripts" "$barred_metadata_dir/bin"
    printf '%s\n' "$1" > "$barred_metadata_repo/project.yml"
    cp "$barred_test_source/Scripts/bump-version.sh" "$barred_metadata_repo/Scripts/"
    cp "$barred_test_source/Makefile" "$barred_metadata_repo/"
    cat > "$barred_metadata_dir/bin/git" <<'STUB'
#!/bin/bash
printf '<%s>' "$@" >> "$GIT_LOG"
printf '\n' >> "$GIT_LOG"
if [ "${1:-}" = push ]; then
    echo 'Fixture blocks every push.' >&2
    exit 97
fi
if [ "${1:-}" = --no-optional-locks ] && [ "${2:-}" = status ] && [ "${BARRED_STATUS_FAILURE:-0}" != 0 ]; then
    printf '%s' "${BARRED_STATUS_PARTIAL:-}"
    exit "$BARRED_STATUS_FAILURE"
fi
exec "$BARRED_REAL_GIT" "$@"
STUB
    chmod +x "$barred_metadata_dir/bin/git"
    metadata_git -c init.defaultBranch=main init -q
    metadata_git add project.yml Scripts/bump-version.sh Makefile
    metadata_git commit -qm 'Fixture baseline'
    metadata_git tag fixture-base
    cp "$barred_metadata_repo/project.yml" "$barred_metadata_dir/before.yml"
    metadata_git ls-files --stage -z > "$barred_metadata_dir/before-index"
    barred_metadata_head=$(metadata_git rev-parse HEAD)
    barred_metadata_tags=$(metadata_git tag --list)
    barred_metadata_status=$(metadata_git status --porcelain=v1)
}

run_metadata() {
    local entry=$1 bump=$2 mode=$3
    local args=("$bump")
    [ "$mode" != push ] || args+=(--push)
    if [ "$entry" = make ]; then
        args=("$barred_real_make" --no-print-directory bump "TYPE=$bump")
        [ "$mode" != push ] || args+=(PUSH=--push)
    else
        args=(/bin/bash Scripts/bump-version.sh "${args[@]}")
    fi
    if (cd "$barred_metadata_repo" && metadata_env \
        PATH="$barred_metadata_dir/bin:/usr/bin:/bin" BARRED_REAL_GIT="$barred_real_git" \
        BARRED_STATUS_FAILURE="${barred_status_failure:-0}" BARRED_STATUS_PARTIAL="${barred_status_partial:-}" \
        GIT_LOG="$barred_metadata_dir/git.log" "${args[@]}") \
        > "$barred_metadata_dir/output" 2> "$barred_metadata_dir/error"; then
        barred_metadata_result=0
    else
        barred_metadata_result=$?
    fi
}

reject_metadata() {
    local entry=$1 mode=$2 bump=$3 document=$4
    metadata_fixture "$document"
    run_metadata "$entry" "$bump" "$mode"
    [ "$barred_metadata_result" != 0 ] || fail "Accepted invalid metadata ($entry/$mode/$bump); tags: $(metadata_git tag --list): $document"
    grep -Eq 'Error:.*(MARKETING_VERSION|[Vv]ersion)' "$barred_metadata_dir/error" || fail 'Missing metadata diagnostic'
    ! grep -q '^Bumping version:' "$barred_metadata_dir/output" || fail 'Invalid metadata emitted release progress'
    cmp -s "$barred_metadata_repo/project.yml" "$barred_metadata_dir/before.yml" || fail 'Rejected metadata changed bytes'
    [ "$(metadata_git rev-parse HEAD)" = "$barred_metadata_head" ] || fail 'Rejected metadata changed HEAD'
    [ "$(metadata_git tag --list)" = "$barred_metadata_tags" ] || fail 'Rejected metadata changed tags'
    [ "$(metadata_git status --porcelain=v1)" = "$barred_metadata_status" ] || fail 'Rejected metadata changed index/worktree state'
    metadata_git ls-files --stage -z > "$barred_metadata_dir/after-index"
    cmp -s "$barred_metadata_dir/before-index" "$barred_metadata_dir/after-index" || fail 'Rejected metadata changed logical index'
    assert_status_only
    barred_cases=$((barred_cases + 1))
}

reject_dirty_worktree() {
    local entry=$1 mode=$2 state=$3 file
    metadata_fixture "$(metadata_document 4.5.6)"
    printf 'Original notes\n' > "$barred_metadata_repo/notes.txt"
    metadata_git add notes.txt
    metadata_git commit -qm 'Fixture notes'
    barred_status_failure=0
    barred_status_partial=''
    case "$state" in
        staged) printf 'Staged notes\n' >> "$barred_metadata_repo/notes.txt"; metadata_git add notes.txt ;;
        unstaged) printf 'Unstaged notes\n' >> "$barred_metadata_repo/notes.txt" ;;
        staged-project) printf '# Staged project note\n' >> "$barred_metadata_repo/project.yml"; metadata_git add project.yml ;;
        unstaged-project) printf '# Unstaged project note\n' >> "$barred_metadata_repo/project.yml" ;;
        untracked)
            mkdir "$barred_metadata_repo/drafts"
            printf 'Private notes\n' > "$barred_metadata_repo/drafts/private notes.txt"
            metadata_git config status.showUntrackedFiles no
            ;;
        mixed)
            printf 'Staged notes\n' >> "$barred_metadata_repo/notes.txt"
            metadata_git add notes.txt
            printf 'Unstaged notes\n' >> "$barred_metadata_repo/notes.txt"
            printf '# Unstaged project note\n' >> "$barred_metadata_repo/project.yml"
            mkdir "$barred_metadata_repo/drafts"
            printf 'Private notes\n' > "$barred_metadata_repo/drafts/private notes.txt"
            ;;
        status-failure|partial-status-failure)
            rm "$barred_metadata_repo/project.yml"
            barred_status_failure=42
            [ "$state" != partial-status-failure ] || barred_status_partial=' M project.yml'
            ;;
    esac
    mkdir "$barred_metadata_dir/before-files"
    for file in project.yml notes.txt Makefile Scripts/bump-version.sh 'drafts/private notes.txt'; do
        if [ -f "$barred_metadata_repo/$file" ]; then
            mkdir -p "$barred_metadata_dir/before-files/$(dirname "$file")"
            cp -p "$barred_metadata_repo/$file" "$barred_metadata_dir/before-files/$file"
        fi
    done
    metadata_git --no-optional-locks status --porcelain=v1 --untracked-files=all > "$barred_metadata_dir/status.before"
    metadata_git --no-optional-locks diff --binary > "$barred_metadata_dir/unstaged.before"
    metadata_git --no-optional-locks diff --cached --binary > "$barred_metadata_dir/staged.before"
    metadata_git rev-parse HEAD > "$barred_metadata_dir/head.before"
    metadata_git tag --list > "$barred_metadata_dir/tags.before"
    cp "$barred_metadata_repo/.git/index" "$barred_metadata_dir/index.before"
    cp "$barred_metadata_repo/.git/config" "$barred_metadata_dir/config.before"

    run_metadata "$entry" patch "$mode"

    [ "$barred_metadata_result" != 0 ] || fail "Accepted $state worktree ($entry/$mode); version commit includes: $(metadata_git show --pretty= --name-only HEAD)"
    cmp -s "$barred_metadata_repo/.git/index" "$barred_metadata_dir/index.before" || fail 'Rejected bump changed index bytes'
    cmp -s "$barred_metadata_repo/.git/config" "$barred_metadata_dir/config.before" || fail 'Rejected bump changed Git configuration'
    if [ "$barred_status_failure" != 0 ]; then
        grep -q 'Could not read Git worktree status' "$barred_metadata_dir/error" || fail 'Git failure did not stop before metadata'
    else
        grep -q 'clean.*worktree' "$barred_metadata_dir/error" || fail 'Missing dirty-worktree diagnostic'
    fi
    ! grep -q '^Bumping version:' "$barred_metadata_dir/output" || fail 'Rejected worktree emitted release progress'
    for file in project.yml notes.txt Makefile Scripts/bump-version.sh 'drafts/private notes.txt'; do
        if [ -f "$barred_metadata_dir/before-files/$file" ]; then
            cmp -s "$barred_metadata_repo/$file" "$barred_metadata_dir/before-files/$file" || fail "Changed fixture file: $file"
            [ "$(stat -f '%Lp' "$barred_metadata_repo/$file")" = "$(stat -f '%Lp' "$barred_metadata_dir/before-files/$file")" ] || fail "Changed fixture mode: $file"
        else
            [ ! -e "$barred_metadata_repo/$file" ] || fail "Created unexpected fixture file: $file"
        fi
    done
    metadata_git --no-optional-locks status --porcelain=v1 --untracked-files=all > "$barred_metadata_dir/status.after"
    metadata_git --no-optional-locks diff --binary > "$barred_metadata_dir/unstaged.after"
    metadata_git --no-optional-locks diff --cached --binary > "$barred_metadata_dir/staged.after"
    metadata_git rev-parse HEAD > "$barred_metadata_dir/head.after"
    metadata_git tag --list > "$barred_metadata_dir/tags.after"
    for file in status unstaged staged head tags; do
        cmp -s "$barred_metadata_dir/$file.before" "$barred_metadata_dir/$file.after" || fail "Rejected bump changed $file"
    done
    assert_status_only
    barred_status_failure=0
    barred_status_partial=''
    barred_cases=$((barred_cases + 1))
}

for entry in direct make; do
    for mode in local push; do
        for state in staged unstaged staged-project unstaged-project untracked mixed status-failure partial-status-failure; do
            reject_dirty_worktree "$entry" "$mode" "$state"
        done
    done
done

for entry in direct make; do
    for mode in local push; do
        for invalid in 4.5.bad 4.bad.6 bad.5.6 01.2.3 1.02.3 1.2.03 \
            -1.2.3 1.2 1.2.3.4 1.2.3-beta 1.2.3+build '1+2.2.3' \
            4.5.9223372036854775808 9223372036854775808.5.6 \
            4.9223372036854775808.6 4.5.18446744073709551617; do
            reject_metadata "$entry" "$mode" minor "$(metadata_document "$invalid")"
        done
        for document in \
            'settings:' \
            '  NOT_MARKETING_VERSION: "4.5.6"' \
            '  # MARKETING_VERSION: "4.5.6"' \
            '  MARKETING_VERSION: ""' \
            '  MARKETING_VERSION: 4.5.6' \
            '  MARKETING_VERSION: "4.5.6" junk' \
            $'  MARKETING_VERSION: "4.5.6"\n  MARKETING_VERSION: "4.5.6"' \
            $'  MARKETING_VERSION: "4.5.6"\n  MARKETING_VERSION:'; do
            reject_metadata "$entry" "$mode" patch "$document"
        done
        reject_metadata "$entry" "$mode" major "$(metadata_document 4.bad.6)"
        reject_metadata "$entry" "$mode" patch "$(metadata_document 4.5.18446744073709551617)"
        for bump in major minor patch; do
            case "$bump" in
                major) version=9223372036854775807.2.3 ;;
                minor) version=4.9223372036854775807.6 ;;
                patch) version=4.5.9223372036854775807 ;;
            esac
            reject_metadata "$entry" "$mode" "$bump" "$(metadata_document "$version")"
        done
        metadata_fixture "$(metadata_document 4.5.6)"
        rm "$barred_metadata_repo/project.yml"
        metadata_git add -u
        metadata_git commit -qm 'Fixture without metadata'
        barred_metadata_head=$(metadata_git rev-parse HEAD)
        metadata_git ls-files --stage -z > "$barred_metadata_dir/before-index"
        barred_metadata_status=$(metadata_git status --porcelain=v1)
        run_metadata "$entry" patch "$mode"
        [ "$barred_metadata_result" != 0 ] || fail 'Missing project metadata was accepted'
        grep -q 'Error:.*MARKETING_VERSION' "$barred_metadata_dir/error" || fail 'Missing project metadata diagnostic'
        [ ! -e "$barred_metadata_repo/project.yml" ] || fail 'Recreated missing metadata'
        [ "$(metadata_git rev-parse HEAD)" = "$barred_metadata_head" ] || fail 'Missing metadata changed HEAD'
        [ "$(metadata_git tag --list)" = "$barred_metadata_tags" ] || fail 'Missing metadata changed tags'
        [ "$(metadata_git status --porcelain=v1)" = "$barred_metadata_status" ] || fail 'Missing metadata changed index/worktree state'
        metadata_git ls-files --stage -z > "$barred_metadata_dir/after-index"
        cmp -s "$barred_metadata_dir/before-index" "$barred_metadata_dir/after-index" || fail 'Rejected metadata changed logical index'
        assert_status_only
        barred_cases=$((barred_cases + 1))
    done
    for scenario in \
        'major 0.0.0 1.0.0' 'minor 0.0.0 0.1.0' 'patch 0.0.0 0.0.1' \
        'major 9.5.6 10.0.0' 'minor 4.9.6 4.10.0' 'patch 4.5.9 4.5.10' \
        'major 9223372036854775806.2.3 9223372036854775807.0.0' \
        'minor 4.9223372036854775806.6 4.9223372036854775807.0' \
        'patch 4.5.9223372036854775806 4.5.9223372036854775807' \
        'major 1.9223372036854775807.9223372036854775807 2.0.0' \
        'minor 9223372036854775807.0.9223372036854775807 9223372036854775807.1.0' \
        'patch 9223372036854775807.9223372036854775807.0 9223372036854775807.9223372036854775807.1'; do
        read -r bump version expected <<< "$scenario"
        metadata_fixture "$(metadata_document "$version")"
        run_metadata "$entry" "$bump" local
        [ "$barred_metadata_result" = 0 ] || fail "Valid metadata rejected: $scenario"
        metadata_document "$expected" > "$barred_metadata_dir/expected.yml"
        cmp -s "$barred_metadata_repo/project.yml" "$barred_metadata_dir/expected.yml" || fail 'Valid bump changed unrelated metadata'
        [ "$(metadata_git rev-parse HEAD^)" = "$barred_metadata_head" ] || fail 'Valid bump did not create one commit'
        [ "$(metadata_git cat-file -t "refs/tags/v$expected")" = tag ] || fail 'Version tag is not annotated'
        [ "$(metadata_git rev-parse "refs/tags/v$expected^{}")" = "$(metadata_git rev-parse HEAD)" ] || fail 'Version tag has wrong target'
        [ -z "$(metadata_git status --porcelain=v1)" ] || fail 'Valid bump left dirty metadata'
        ! grep -q '<push>' "$barred_metadata_dir/git.log" || fail 'Local fixture requested push'
        barred_cases=$((barred_cases + 1))
    done
    metadata_fixture $'settings:\n  NOT_MARKETING_VERSION: "99.99.99"\n  # MARKETING_VERSION: "88.88.88"\n  MARKETING_VERSION  :   "4.5.6"   # Keep "quoted" notes\n  CURRENT_PROJECT_VERSION: 78'
    run_metadata "$entry" patch local
    [ "$barred_metadata_result" = 0 ] || fail 'Valid spacing/comments were rejected'
    printf '%s\n' $'settings:\n  NOT_MARKETING_VERSION: "99.99.99"\n  # MARKETING_VERSION: "88.88.88"\n  MARKETING_VERSION  :   "4.5.7"   # Keep "quoted" notes\n  CURRENT_PROJECT_VERSION: 78' > "$barred_metadata_dir/expected.yml"
    cmp -s "$barred_metadata_repo/project.yml" "$barred_metadata_dir/expected.yml" || fail 'Valid spacing/comments changed'
    [ -z "$(metadata_git status --porcelain=v1)" ] || fail 'Spaced metadata did not leave a clean fixture'
    barred_cases=$((barred_cases + 1))
done

echo "Passed $barred_cases version-helper scenarios; real Git mutations stayed in disposable fixtures and pushes were blocked."
