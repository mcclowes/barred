SCHEME = Barred
PROJECT = Barred.xcodeproj
BUILD_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$NF}')

.PHONY: build release app run test format format-check lint clean xcode help

build: ## Debug build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug build

release: ## Release build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release build

app: ## Build .app bundle (signed, notarizable)
	./Scripts/build-app.sh

run: build ## Build and run
	open "$(BUILD_DIR)/Barred.app"

test: ## Run tests
	xcodebuild -project $(PROJECT) -scheme BarredTests -configuration Debug test

format: ## Auto-format Swift files
	swiftformat Sources/ Tests/

format-check: ## Check formatting without changes
	swiftformat --lint Sources/ Tests/

lint: format-check ## Alias for format-check

xcode: ## Regenerate Xcode project from project.yml
	xcodegen generate

clean: ## Remove build artifacts
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf .build/Barred.app .build/Barred.zip

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-12s %s\n", $$1, $$2}'
