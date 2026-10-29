#!/usr/bin/env bash
set -euo pipefail

# Bump the project version (major/minor/patch), commit, tag, and optionally push.
# Usage: ./Scripts/bump-version.sh <major|minor|patch> [--push]

BUMP_TYPE="${1:-}"
PUSH="${2:-}"
PROJECT_YML="project.yml"

if [[ "$#" -lt 1 || "$#" -gt 2 || ! "$BUMP_TYPE" =~ ^(major|minor|patch)$ ]] \
  || { [ "$#" -eq 2 ] && [ "$PUSH" != "--push" ]; }; then
  echo "Usage: $0 <major|minor|patch> [--push]" >&2
  exit 2
fi

version_error() {
  echo "Error: $1" >&2
  exit 1
}

VERSION_SETTINGS=$(awk '
  /^[[:space:]]*MARKETING_VERSION[[:space:]]*:/ { count++; setting = $0 }
  END { print count + 0; if (count == 1) print setting }
' "$PROJECT_YML") || version_error "Could not read MARKETING_VERSION from $PROJECT_YML."
if [[ "${VERSION_SETTINGS%%$'\n'*}" != 1 ]]; then
  version_error "Expected exactly one MARKETING_VERSION setting in $PROJECT_YML."
fi
VERSION_LINE=${VERSION_SETTINGS#*$'\n'}
VERSION_PATTERN='^[[:space:]]*MARKETING_VERSION[[:space:]]*:[[:space:]]*"((0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*))"[[:space:]]*(#.*)?$'
if [[ ! "$VERSION_LINE" =~ $VERSION_PATTERN ]]; then
  version_error 'MARKETING_VERSION must be a quoted major.minor.patch without leading zeroes.'
fi
CURRENT_VERSION=${BASH_REMATCH[1]}

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
for COMPONENT in "$MAJOR" "$MINOR" "$PATCH"; do
  if ! DECIMAL_COMPONENT=$(printf '%d' "$COMPONENT" 2>/dev/null) || [[ "$DECIMAL_COMPONENT" != "$COMPONENT" ]]; then
    version_error 'MARKETING_VERSION exceeds the supported integer range.'
  fi
done

case "$BUMP_TYPE" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
if (( MAJOR < 0 || MINOR < 0 || PATCH < 0 )); then
  version_error 'Version increment exceeds the supported integer range.'
fi

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${NEW_VERSION}"

echo "Bumping version: $CURRENT_VERSION -> $NEW_VERSION ($BUMP_TYPE)"

# Update project.yml
sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION[[:space:]]*:[[:space:]]*\")[0-9]+\.[0-9]+\.[0-9]+(\"[[:space:]]*(#.*)?)$/\1${NEW_VERSION}\2/" "$PROJECT_YML"

# Commit and tag
git add "$PROJECT_YML"
git commit -m "Bump version to ${NEW_VERSION}"
git tag -a "$TAG" -m "Release ${TAG}"

echo "Created commit and tag: $TAG"

if [[ "$PUSH" == "--push" ]]; then
  git push origin HEAD
  git push origin "$TAG"
  echo "Pushed commit and tag to origin"
else
  echo "Run 'git push origin HEAD && git push origin $TAG' to trigger the release workflow."
fi
