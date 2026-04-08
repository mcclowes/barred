.PHONY: build release app run test clean help

build: ## Debug build
	swift build

release: ## Release build
	swift build -c release

app: ## Build .app bundle
	./Scripts/build-app.sh

test: ## Run tests
	swift test

run: app ## Build and open .app bundle
	open .build/Barman.app

clean: ## Remove build artifacts
	swift package clean
	rm -rf .build/Barman.app

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
