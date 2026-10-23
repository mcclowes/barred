#!/bin/bash
set -euo pipefail
set -f

if [ "$#" -ne 1 ]; then
    echo 'Usage: cask-architectures.sh <release executable>' >&2
    exit 2
fi

release_architectures=$(lipo -archs "$1")
cask_architectures=''
for architecture in $release_architectures; do
    case "$architecture" in
        arm64|x86_64) ;;
        *) echo "Unsupported release architecture: $architecture" >&2; exit 1 ;;
    esac
    if [ -n "$cask_architectures" ]; then
        cask_architectures+=', '
    fi
    cask_architectures+=":$architecture"
done

if [ -z "$cask_architectures" ]; then
    echo 'Release binary contains no supported architectures' >&2
    exit 1
fi
printf '%s\n' "$cask_architectures"
