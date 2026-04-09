# Barred — code review

Last reviewed: 2026-04-09

---

## Previously resolved

Items from prior reviews that have been addressed:

- Protocol abstractions added (`AccessibilityQuerying`, `MenuBarDetecting`, `PreferencesStoring`, `SectionDividing`) with constructor injection in `MenuBarController`
- `showBarredBarOnClick` preference wired up in `BarredApp.swift` (Option-click for opposite behaviour)
- `OverlayWindow.swift` dead code removed
- Hardcoded 1-second sleep replaced with `detector.waitForFirstScan()` using `CheckedContinuation`
- `restoreAll()` now calls `detector.stopScanning()`
- Auto-hide race guard added (`guard isBarredBarVisible else { return }`)
- `MenuBarControllerTests` and `MenuBarDetectorTests` added (11 tests using mock services)
- os.Logger added to `AppDelegate`, `MenuBarController`, `MenuBarDetector`, `SectionDivider`
- SwiftLint added with `.swiftlint.yml` and `make lint` / `make lint-fix` targets
- `Package.swift` removed — unified on xcodebuild for CI and release (`build-app.sh` updated)
- Stable item IDs using `bundleIdentifier:title` instead of PID-based IDs
- `appIcon` cached as stored property at creation time (was doing filesystem I/O per render)
- Accessibility permission polled on each scan cycle via `checkTrust()`
- Multi-monitor deduplication fixed to use `NSScreen.main?.frame.contains()` instead of `x >= 0`
- Slider/model range aligned — model clamped to 1...15 to match slider
- Ultrawide divider cap increased from 10,000px to 20,000px
- os.Logger added to `AccessibilityService` and `PreferencesStore`
- `#selector(AppDelegate.toggleBarredBarFromDivider)` replaced with closure callback in `SectionDivider`
- Redundant `.environment(controller)` removed from `SettingsView`
- `build-app.sh` updated to use xcodebuild instead of `swift build`; `spctl` now hard-fails in CI
- CI pinned to `macos-15` instead of `macos-latest`
- Makefile target renamed `xcode` → `generate` (aligned with Clipped)

---

## Open items

### High priority

#### 1. Deprecated `tabItem` API (blocked by deployment target)

**File:** `SettingsView.swift:10,15,20`

`.tabItem { Label(...) }` should migrate to the `Tab` type, but `Tab` requires macOS 15. Blocked until deployment target is raised from macOS 14.

#### 2. `CGWindowListCopyWindowInfo` deprecated in macOS 15

**File:** `MenuBarDetector.swift`

The fallback detection path and window-ID matching use this API. Apple is moving to `ScreenCaptureKit`. Tracked in #3.

### Medium priority

#### 3. Missing keyboard shortcuts in popover

No global hotkey or keyboard navigation in the popover. Power users need keyboard-driven access. Tracked in #4.

---

## Testing gaps

Tests have improved (34 tests across 8 files with mocks), but gaps remain:

| Gap | Priority |
|-----|----------|
| `MenuBarDetector.scan()` — actual AX/window detection logic | High |
| `MenuBarDetector.deduplicateAcrossScreens()` | High |
| `SectionDivider.expand()/collapse()` with real status item | Medium |
| `AccessibilityService` enumeration logic (beyond trivial paths) | Medium |
| View rendering / interaction tests | Low |

---

## Cross-project alignment with Clipped

| Item | Status |
|------|--------|
| Protocol-based DI | Done |
| SwiftFormat + SwiftLint | Done |
| os.Logger on all services | Done |
| Makefile `generate` target | Done |
| Logger subsystem casing (`com.mcclowes.barred` vs `com.mcclowes.Clipped`) | Standardize to lowercase |
| Pin CI macOS version | Done |
| `.swiftlint.yml` rule alignment | Review and align opt-in rules |
