# Barred

macOS menu bar manager — detects and manages menu bar items from other apps using Accessibility APIs.

## Stack

- Swift 6, SwiftUI
- macOS 14+ (Sonoma)
- Xcode project via xcodegen (`project.yml` → `Barred.xcodeproj`)
- LSUIElement app (no dock icon)

## Build

```bash
make build               # debug build (xcodebuild)
make release             # release build
make app                 # build .app bundle via Scripts/build-app.sh
make run                 # build and run
make test                # run tests
make xcode               # regenerate Xcode project from project.yml
make clean               # remove build artifacts
make help                # show available targets
```

## Architecture

- `BarredApp.swift` — app entry point
- `Services/` — core logic (AccessibilityService, MenuBarDetector, MenuBarController, PreferencesStore, SectionDivider)
- `Models/` — data types (MenuBarItem, UserPreferences)
- `Views/` — SwiftUI views (BarredMenuView, SettingsView, OnboardingView, MenuBarItemRow)
- `Utilities/` — helpers (AXExtensions, OverlayWindow)
- `Resources/` — Info.plist, Barred.entitlements, AppIcon.icns

## Notes

- Requires Accessibility permission (System Settings > Privacy & Security > Accessibility)
- Tests in `Tests/BarredTests/` (run with `make test`)
- CI/CD: GitHub Actions release workflow (`.github/workflows/release.yml`) — builds, signs, notarizes, creates GitHub release, and updates Homebrew cask (`brew tap mcclowes/barred`)
