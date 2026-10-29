# Commands

Run commands from the repository root. Native builds require macOS and Xcode;
project generation requires XcodeGen. Formatting and lint use SwiftFormat and
SwiftLint. Shell helper tests use temporary fixtures and stubbed build/signing
tools, without launching Barred or submitting a notarization request.

## Checks

- Packaging helper tests: `make test-build-helper` - checks metadata, signing arguments, preparation failures, promotion rollback, handled signals, recovery backups, and dummy notarization with isolated fixtures #quick #safe #ci
- Cask helper tests: `make test-cask-helper` - checks release architecture detection with a stubbed inspector #quick #safe #ci
- Version helper tests: `make test-bump-helper` - checks clean worktrees, direct-helper and literal Make arguments, metadata, integer boundaries, local tag collisions, lookup failures, and valid bumps in disposable repositories with blocked pushes #quick #safe #ci
- Make and launch tests: `make test-run` - checks project/scheme arguments, development signing, Debug launch paths, failures, and cleanup with stubbed tools and disposable outputs #quick #safe #ci
- Release paths: `make test-release-paths` - checks both release settings lookups with fake Xcode #quick #safe #ci
- Hook installer tests: `make test-install-hooks` - checks Git-resolved destinations, replacement failures, and signal cleanup in disposable repositories #quick #safe #ci
- Shell syntax: `for script in Scripts/*.sh; do bash -n "$script" || exit; done` #quick #safe #ci
- Shell lint: `shellcheck Scripts/*.sh` #quick #safe #ci
- Swift format check: `make format-check` - checks formatting without changing source #quick #safe
- Swift lint: `make lint` #quick #safe #ci
- Catalog check: `clip commands check --strict` - checks decorators and Makefile coverage #quick #safe
- Target help: `make help` #quick #safe

## Native app

Hosted native tests launch Barred.app. Its current startup creates menu bar
items, starts the controller, and records onboarding in standard preferences.
Run these tests in an isolated macOS account or CI when those effects matter.
App launch can request Accessibility access and rearrange menu bar items.

- Debug build: `make build` #safe #slow
- Release build: `make release` #safe #slow
- Native tests: `make test` - launches the app test host and runs Swift Testing #writes #slow #ci
- Build and launch: `make run` - builds with development signing and opens Barred.app on the current desktop #writes #interactive #slow

## Source and local setup

- Format source: `make format` - rewrites Swift source and tests #quick #writes
- Fix Swift lint: `make lint-fix` - applies available source fixes #quick #writes
- Generate project: `make generate` - rewrites Barred.xcodeproj from project.yml #quick #writes
- Install commit hook: `make install-hooks` - replaces the hook at Git's active destination, including core.hooksPath; linked worktrees normally share the default hook; preparation failures preserve the previous hook #quick #writes
- Clean build output: `make clean` - removes Xcode output and .build/Barred.app and .build/Barred.zip #safe

## Release actions

Packaging regenerates the Xcode project, replaces the local app/zip, signs it,
and submits it for notarization if the required Apple credentials are present.
Version bumps modify project.yml, create a commit and tag, and push when
PUSH=--push is supplied. Neither command is a routine check.

- Package app: `make app` - builds, signs, and optionally notarizes the release bundle #destructive #slow
- Bump version: `make bump TYPE=patch` - use minor or major as needed; PUSH=--push also triggers the release workflow #destructive
