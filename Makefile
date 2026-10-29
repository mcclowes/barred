SCHEME = Barred
PROJECT = Barred.xcodeproj
DEV_CODE_SIGN_IDENTITY ?= Apple Development
DEV_DEVELOPMENT_TEAM ?= BCB43KG62T

.PHONY: build release app run test test-build-helper test-cask-helper test-bump-helper test-run test-release-paths test-install-hooks format format-check lint clean generate install-hooks bump help

## Build

build: ## Debug build
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug build

release: ## Release build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

app: ## Build .app bundle (signed, notarizable)
	./Scripts/build-app.sh

run: ## Build and run with persistent development signing
	xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug \
		CODE_SIGN_IDENTITY="$(DEV_CODE_SIGN_IDENTITY)" DEVELOPMENT_TEAM="$(DEV_DEVELOPMENT_TEAM)" \
		CODE_SIGN_STYLE=Manual build
	@BUILD_SETTINGS=$$(xcodebuild -project "$(PROJECT)" -scheme "$(SCHEME)" -configuration Debug -showBuildSettings) || exit $$?; \
	BUILT_DIR=$$(printf '%s\n' "$$BUILD_SETTINGS" | awk '/^[[:space:]]*BUILT_PRODUCTS_DIR[[:space:]]*=/ { sub(/^[[:space:]]*BUILT_PRODUCTS_DIR[[:space:]]*=[[:space:]]*/, ""); print; exit }'); \
	test -n "$$BUILT_DIR" || { echo 'Xcode did not report a build products directory.' >&2; exit 1; }; \
	open "$$BUILT_DIR/Barred.app"

## Test

test: ## Run tests
	xcodebuild -project $(PROJECT) -scheme BarredTests -configuration Debug test

test-build-helper: ## Check build helper with stubbed signing tools
	bash Scripts/test-build-app.sh

test-cask-helper: ## Check release architecture metadata with a stubbed inspector
	bash Scripts/test-cask-architectures.sh

test-bump-helper: ## Check version helper arguments with stubbed Git
	bash Scripts/test-bump-version.sh

test-run: ## Check launch paths with stubbed build and launch tools
	bash Scripts/test-run.sh

test-release-paths: ## Check release settings lookups with fake Xcode
	bash Scripts/test-release-paths.sh

test-install-hooks: ## Check hook installation in disposable repositories
	bash Scripts/test-install-hooks.sh

## Lint & format

format: ## Auto-format Swift files (swiftformat)
	swiftformat Sources/ Tests/

format-check: ## Check formatting without changes
	swiftformat --lint Sources/ Tests/

lint: ## Run SwiftLint
	swiftlint lint --strict

lint-fix: ## Auto-fix SwiftLint violations
	swiftlint lint --fix

## Hooks

install-hooks: ## Install git pre-commit hook
	@set -e; \
	hook_dir=$$(git rev-parse --path-format=absolute --git-path hooks); \
	test -n "$$hook_dir"; \
	hook="$$hook_dir/pre-commit"; \
	mkdir -p "$$hook_dir"; \
	if [ -d "$$hook" ]; then echo 'Hook destination is a directory.' >&2; exit 1; fi; \
	staged=$$(mktemp "$$hook_dir/.pre-commit.XXXXXX"); \
	trap 'rm -f "$$staged"' 0; \
	trap 'exit 129' HUP; trap 'exit 130' INT; trap 'exit 143' TERM; \
	cp Scripts/pre-commit "$$staged"; \
	chmod +x "$$staged"; \
	mv -f "$$staged" "$$hook"; \
	echo "Pre-commit hook installed."

## Version

bump: ## Bump version (usage: make bump TYPE=patch|minor|major [PUSH=--push])
	./Scripts/bump-version.sh $(TYPE) $(PUSH)

## Project

generate: ## Regenerate Xcode project from project.yml
	xcodegen generate

clean: ## Remove build artifacts
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf .build/Barred.app .build/Barred.zip

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-14s %s\n", $$1, $$2}'
