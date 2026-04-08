# Barman

macOS menu bar manager — detects and manages menu bar items from other apps using Accessibility APIs.

## Stack

- Swift 6, SwiftUI
- macOS 14+ (Sonoma)
- Swift Package Manager (no Xcode project)
- LSUIElement app (no dock icon)

## Build

```bash
swift build              # debug build
swift build -c release   # release build
./Scripts/build-app.sh   # build .app bundle to .build/Barman.app
```

## Architecture

- `BarmanApp.swift` — app entry point
- `Services/` — core logic (AccessibilityService, MenuBarDetector, MenuBarController, PreferencesStore, SectionDivider)
- `Models/` — data types (MenuBarItem, UserPreferences)
- `Views/` — SwiftUI views (BarmanMenuView, SettingsView, OnboardingView, MenuBarItemRow)
- `Utilities/` — helpers (AXExtensions, OverlayWindow)

## Notes

- Requires Accessibility permission (System Settings > Privacy & Security > Accessibility)
- No tests yet
