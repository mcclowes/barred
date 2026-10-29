#!/bin/bash
set -euo pipefail
unset MAKEFLAGS MFLAGS MAKEOVERRIDES MAKELEVEL MAKEFILES BASH_ENV ENV
for variable in "${!GIT_@}"; do unset "$variable"; done
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0

barred_test_source="$(cd "$(dirname "$0")/.." && pwd)"
barred_test_make=${BARRED_TEST_MAKE:-/usr/bin/make}
barred_test_git=$(command -v git)
barred_test_temp=$(mktemp -d "${TMPDIR:-/tmp}/barred-install-hooks.XXXXXX")
trap 'rm -rf "$barred_test_temp"' EXIT
barred_test_path=$PATH
fail() { echo "$1" >&2; exit 1; }

file_mode() {
    local mode
    if mode=$(stat -f '%Lp' "$1" 2>/dev/null); then
        printf '%s\n' "$mode"
    else
        stat -c '%a' "$1"
    fi
}

snapshot() {
    "$barred_test_git" -C "$project" rev-parse HEAD
    "$barred_test_git" -C "$project" for-each-ref --format='%(refname) %(objectname)'
    "$barred_test_git" -C "$project" status --porcelain=v1
    "$barred_test_git" -C "$project" ls-files --stage
    "$barred_test_git" -C "$project" diff
    "$barred_test_git" -C "$project" diff --cached
    cksum "$index_path" "$config_path"
    "$barred_test_git" -C "$project" ls-files -z | while IFS= read -r -d '' file; do
        cksum "$project/$file"
        file_mode "$project/$file"
    done
    cksum "$project/.untracked-note"
}

barred_cases=0
for scenario in ordinary worktree relative absolute worktree-relative symlink hardlink \
    partial-copy chmod-failure promotion-failure git-failure mkdir-failure mktemp-failure \
    signal-HUP signal-INT signal-TERM directory symlink-directory; do
    case_root="$barred_test_temp/$scenario with spaces"
    project="$case_root/project with spaces"
    mkdir -p "$project/Scripts" "$case_root/bin"
    cp "$barred_test_source/Makefile" "$project/Makefile"
    cat > "$project/Scripts/pre-commit" <<'HOOK'
#!/bin/sh
printf '%s\n' 'new hook ran' >> "$BARRED_INSTALL_TEST_MARKER"
HOOK
    printf 'baseline\n' > "$project/notes.txt"
    printf '/relative hooks/\n' > "$project/.gitignore"
    "$barred_test_git" -C "$project" init -q
    "$barred_test_git" -C "$project" config user.name 'Hook fixture'
    "$barred_test_git" -C "$project" config user.email fixture@example.invalid
    "$barred_test_git" -C "$project" config commit.gpgSign false
    "$barred_test_git" -C "$project" config tag.gpgSign false
    "$barred_test_git" -C "$project" add Makefile Scripts/pre-commit notes.txt .gitignore
    "$barred_test_git" -C "$project" -c core.hooksPath=/dev/null commit -qm 'Fixture base'
    printf 'saved change\n' > "$project/notes.txt"
    "$barred_test_git" -C "$project" -c core.hooksPath=/dev/null stash push -qm 'Preserved fixture stash'
    main_project=$project
    case "$scenario" in
        worktree|worktree-relative)
            project="$case_root/linked checkout"
            "$barred_test_git" -C "$main_project" -c core.hooksPath=/dev/null \
                worktree add -qb fixture "$project"
            ;;
    esac
    default_hook=$("$barred_test_git" -C "$project" rev-parse --path-format=absolute --git-path hooks/pre-commit)
    mkdir -p "$(dirname "$default_hook")"
    printf '#!/bin/sh\nexit 0\n' > "$default_hook"
    cp -p "$default_hook" "$case_root/default-hook"
    case "$scenario" in
        relative|worktree-relative) "$barred_test_git" -C "$project" config core.hooksPath 'relative hooks' ;;
        absolute) "$barred_test_git" -C "$project" config core.hooksPath "$case_root/absolute hooks" ;;
    esac
    printf 'unstaged change\n' > "$project/notes.txt"
    printf 'untracked content\n' > "$project/.untracked-note"

    hook=$("$barred_test_git" -C "$project" rev-parse --path-format=absolute --git-path hooks/pre-commit)
    mkdir -p "$(dirname "$hook")"
    printf '#!/bin/sh\nexit 0\n' > "$hook"
    chmod 750 "$hook"
    cp -p "$hook" "$case_root/old-hook"
    case "$scenario" in
        symlink)
            mv "$hook" "$case_root/external hook"
            ln -s "$case_root/external hook" "$hook"
            ;;
        hardlink) ln "$hook" "$case_root/external hook" ;;
        directory)
            rm "$hook"
            mkdir "$hook"
            printf 'directory content\n' > "$hook/keep"
            ;;
        symlink-directory)
            rm "$hook"
            mkdir "$case_root/external directory"
            printf 'directory content\n' > "$case_root/external directory/keep"
            ln -s "$case_root/external directory" "$hook"
            ;;
    esac
    old_mode=$(file_mode "$hook")
    index_path=$("$barred_test_git" -C "$project" rev-parse --path-format=absolute --git-path index)
    config_path=$("$barred_test_git" -C "$project" rev-parse --path-format=absolute --git-path config)
    snapshot > "$case_root/before"

    cat > "$case_root/tool-stub" <<'STUB'
#!/bin/sh
tool=${0##*/}
case "$tool:$BARRED_INSTALL_TEST_MODE" in
    git:git-failure) printf '/unusable/path\n'; exit 42 ;;
    mkdir:mkdir-failure|mktemp:mktemp-failure|chmod:chmod-failure|mv:promotion-failure) exit 42 ;;
    cp:partial-copy) printf 'partial replacement\n' > "$2"; exit 42 ;;
    cp:signal-*)
        printf 'partial replacement\n' > "$2"
        kill -"${BARRED_INSTALL_TEST_MODE#signal-}" "$PPID"
        exit 0
        ;;
esac
case "$tool" in
    git) exec "$BARRED_INSTALL_TEST_GIT" "$@" ;;
    mktemp) exec /usr/bin/mktemp "$@" ;;
    *) exec "/bin/$tool" "$@" ;;
esac
STUB
    for tool in git mkdir mktemp cp chmod mv; do
        cp "$case_root/tool-stub" "$case_root/bin/$tool"
        chmod +x "$case_root/bin/$tool"
    done
    if BARRED_INSTALL_TEST_MODE="$scenario" BARRED_INSTALL_TEST_GIT="$barred_test_git" \
        PATH="$case_root/bin:$barred_test_path" "$barred_test_make" -s -C "$project" install-hooks \
        > "$case_root/install.log" 2>&1; then
        result=0
    else
        result=$?
    fi
    case "$scenario" in
        ordinary|worktree|relative|absolute|worktree-relative|symlink|hardlink)
            [ "$result" = 0 ] || { cat "$case_root/install.log" >&2; fail "$scenario failed"; }
            cmp -s "$hook" "$project/Scripts/pre-commit" || fail "$scenario installed the wrong payload"
            [ -x "$hook" ] && [ ! -L "$hook" ] || fail "$scenario did not install a regular executable hook"
            grep -q 'Pre-commit hook installed' "$case_root/install.log" || fail "$scenario omitted success"
            ;;
        *)
            [ "$result" != 0 ] || fail "$scenario unexpectedly succeeded"
            if [ "$scenario" = directory ] || [ "$scenario" = symlink-directory ]; then
                [ "$(cat "$hook/keep")" = 'directory content' ] || fail "$scenario changed the directory"
                [ "$(find -L "$hook" -type f | wc -l | tr -d ' ')" = 1 ] || fail "$scenario wrote into the directory"
                if [ "$scenario" = symlink-directory ]; then
                    [ "$(readlink "$hook")" = "$case_root/external directory" ] || fail "$scenario changed the symlink"
                fi
            else
                cmp -s "$hook" "$case_root/old-hook" || fail "$scenario changed the previous hook"
            fi
            [ "$(file_mode "$hook")" = "$old_mode" ] || fail "$scenario changed previous hook permissions"
            ! grep -q 'Pre-commit hook installed' "$case_root/install.log" || fail "$scenario printed success"
            ;;
    esac
    if [ "$scenario" = symlink ] || [ "$scenario" = hardlink ]; then
        cmp -s "$case_root/external hook" "$case_root/old-hook" || fail "$scenario changed the other link"
        [ "$(file_mode "$case_root/external hook")" = "$(file_mode "$case_root/old-hook")" ] \
            || fail "$scenario changed the other link's permissions"
    fi
    if [ "$hook" != "$default_hook" ]; then
        cmp -s "$default_hook" "$case_root/default-hook" || fail "$scenario changed the default hook"
    fi
    snapshot > "$case_root/after"
    cmp -s "$case_root/before" "$case_root/after" || fail "$scenario changed repository state"
    [ -z "$(find "$(dirname "$hook")" -name '.pre-commit.*' -print)" ] || fail "$scenario left staging"
    if [ "$result" = 0 ]; then
        BARRED_INSTALL_TEST_MARKER="$case_root/hook-ran" "$barred_test_git" -C "$project" \
            commit --allow-empty -qm 'Exercise installed fixture hook'
        [ "$(cat "$case_root/hook-ran")" = 'new hook ran' ] || fail "$scenario hook was not executed by Git"
    fi
    barred_cases=$((barred_cases + 1))
done
echo "Passed $barred_cases hook-installer scenarios in disposable repositories."
