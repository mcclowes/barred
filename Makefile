.PHONY: build release app run clean

build:
	swift build

release:
	swift build -c release

app: ## Build .app bundle
	./Scripts/build-app.sh

run: build ## Build and run debug binary
	.build/debug/Barman

run-app: app ## Build and open .app bundle
	open .build/Barman.app

clean:
	swift package clean
	rm -rf .build/Barman.app

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
