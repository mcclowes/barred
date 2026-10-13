# Commands

Run commands from the repository root. Native builds require macOS and Xcode;
project generation requires XcodeGen. Formatting and lint use SwiftFormat and
SwiftLint. Shell helper tests use temporary fixtures and stubbed build/signing
tools, without launching Barred or submitting a notarization request.

## Checks

- Packaging helper tests: `make test-build-helper` - checks signing arguments and app metadata with isolated fixtures #quick #safe #ci
- Cask helper tests: `make test-cask-helper` - checks release architecture detection with a stubbed inspector #quick #safe #ci
- Shell syntax: `bash -n Scripts/build-app.sh Scripts/test-build-app.sh Scripts/cask-architectures.sh Scripts/test-cask-architectures.sh` #quick #safe #ci
- Shell lint: `shellcheck Scripts/build-app.sh Scripts/test-build-app.sh Scripts/cask-architectures.sh Scripts/test-cask-architectures.sh` #quick #safe #ci
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
- Build and launch: `make run` - opens Barred.app on the current desktop #writes #interactive #slow

## Source and local setup

- Format source: `make format` - rewrites Swift source and tests #quick #writes
- Fix Swift lint: `make lint-fix` - applies available source fixes #quick #writes
- Generate project: `make generate` - rewrites Barred.xcodeproj from project.yml #quick #writes
- Install commit hook: `make install-hooks` - replaces this checkout's pre-commit hook #quick #writes
- Clean build output: `make clean` - removes Xcode output and .build/Barred.app and .build/Barred.zip #safe

## Release actions

Packaging regenerates the Xcode project, replaces the local app/zip, signs it,
and submits it for notarization if the required Apple credentials are present.
Version bumps modify project.yml, create a commit and tag, and push when
PUSH=--push is supplied. Neither command is a routine check.

- Package app: `make app` - builds, signs, and optionally notarizes the release bundle #destructive #slow
- Bump version: `make bump TYPE=patch` - use minor or major as needed; PUSH=--push also triggers the release workflow #destructive
