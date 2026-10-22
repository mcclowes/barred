# Commands

Barred is a Swift 6 macOS menu bar manager. Requires Xcode 16+ and XcodeGen;
quality checks also need SwiftLint and SwiftFormat. Project documentation is in `docs/`.

- Build and run: `make run` - Build Debug with Apple Development signing and launch Barred. Requires a signing identity in Keychain and an initial Accessibility approval. #quick
- Debug build: `make build` - Build the macOS app without launching it. #quick
- Run tests: `make test` - Run the BarredTests Xcode scheme. #quick
- Lint Swift: `make lint` - Run SwiftLint in strict mode. #quick
- Check formatting: `make format-check` - Check Swift formatting without modifying files. #quick
- Regenerate Xcode project: `make generate` - Regenerate Barred.xcodeproj from project.yml. #quick
- Build app bundle: `make app` - Build the release app bundle using Scripts/build-app.sh. #quick

## Layout #auto

Open a terminal showing available Make targets. Builds, app launches, and tests run on demand.

- Project terminal: `make help` - Show the project's task catalog and leave a shell ready for work. #primary
