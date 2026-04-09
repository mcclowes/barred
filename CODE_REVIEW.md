# Barred — code review

Reviewed: 2026-04-09 (second pass — prior review items #2, #3, #5, #6, #8, #11, #12, #14, #18, #22, #23, #24, #27, #30, #31 have been addressed)

---

## Architecture

### 1. No protocol abstractions — still untestable

**Files:** `MenuBarController.swift`, `AccessibilityService.swift`, `MenuBarDetector.swift`, `SectionDivider.swift`

The environment-injection refactor was a good step, but the underlying problem remains: every service is a concrete class with no protocol boundary. You cannot:

- Unit-test `MenuBarController` without triggering real AX queries and creating real `NSStatusItem`s
- Test `MenuBarDetector` without a running accessibility service
- Use SwiftUI previews for any view that depends on the controller
- Write integration tests with deterministic fake data

**Why this matters for juniors:** Protocols aren't about "writing more code." They define the *contract* between components. When you can say "`MenuBarDetector` depends on something that conforms to `AccessibilityQuerying`," you've made the dependency explicit and replaceable. Without that, every class is welded to its collaborators.

**Recommendation:** Start with `AccessibilityService` — it's the hardest to test directly (requires OS permissions) and the easiest to stub:

```swift
protocol AccessibilityQuerying: Sendable {
    var isTrusted: Bool { get }
    func checkTrust()
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo]
}
```

Then `MenuBarDetector(accessibilityService: any AccessibilityQuerying)`. In tests, inject a stub that returns canned data.

### 2. `showBarredBarOnClick` preference exists but is never used

**Files:** `UserPreferences.swift:5`, `GeneralSettingsView` (`SettingsView.swift:117`), `BarredApp.swift:35-53`

There's a toggle in settings. There's a property in the model. But `statusItemClicked` in `AppDelegate` *unconditionally* calls `controller.toggleBarredBar()` on every click regardless of this setting. The preference is dead — it's stored, persisted, and rendered, but never read where it matters.

**Why this matters for juniors:** A feature that's half-implemented is worse than a feature that doesn't exist. It confuses users ("why doesn't this toggle do anything?") and future engineers ("this preference is used somewhere, I'd better not remove it"). Either wire it up or delete it entirely. If you're not sure when you'll get to it, at least leave the toggle disabled with a tooltip.

### 3. `OverlayWindow.swift` is dead code — 44 lines shipping to zero users

**File:** `Sources/Barred/Utilities/OverlayWindow.swift`

This entire file is defined, compiled, and shipped in the binary but never instantiated anywhere. No view, service, or controller references it.

**Why this matters for juniors:** Dead code has a real cost. It increases binary size, cognitive load ("what does this do? is it important?"), and maintenance surface ("do I need to update this when I change the window layer?"). Either it's part of a planned feature (in which case it should be on a feature branch, not main) or it's abandoned (in which case delete it). Git preserves history — you can always bring it back.

### 4. Two build systems that can silently diverge

**Files:** `Package.swift`, `project.yml`, `Makefile`, `Scripts/build-app.sh`

The project has:
- `project.yml` (XcodeGen) generating `Barred.xcodeproj` — used by `make build`, `make test`
- `Package.swift` (SPM) — used by `Scripts/build-app.sh` (`swift build -c release`)
- CI runs `make build && make test` (xcodebuild)
- Release runs `build-app.sh` (SPM)

This means your CI tests one build and your release ships another. If the Xcode project and SPM package have different source file lists, compile flags, or resource handling, you'll ship bugs that CI never caught.

**Why this matters for juniors:** "It works on CI" means nothing if CI and release don't build the same thing. Pick one build system. If you need xcodebuild for tests (because they need a host app for AX), fine — but the release build should use the same system, or you need explicit tests that verify both produce identical artifacts.

---

## Concurrency and correctness

### 5. `start()` uses a hardcoded 1-second sleep as synchronization

**File:** `MenuBarController.swift:32-37`

```swift
func start() {
    sectionDivider.setUp()
    Task {
        try? await Task.sleep(for: .seconds(1))
        hideSection()
    }
}
```

This waits 1 second before hiding the section, presumably to let the first scan complete. But `scan()` does AX queries against every running app — on a slow machine or with many apps, 1 second may not be enough. On a fast machine, you're wasting 1 second of visual glitch where items are visible then hide.

**Why this matters for juniors:** Hardcoded delays are never the right synchronization mechanism. They're a race condition with a probability dial. The correct approach is to wait for the scan to actually complete — e.g., have `startScanning()` return or signal after the first scan, or use an `AsyncStream` of scan results.

### 6. `restoreAll()` doesn't stop the scanner

**File:** `MenuBarController.swift:54-57`

```swift
func restoreAll() {
    cancelAutoHide()
    sectionDivider.collapse()
}
```

Called on `applicationWillTerminate`, this cancels the auto-hide timer and collapses the divider, but `detector.scanTask` keeps running its 3-second loop until process death. This is mostly harmless at quit time, but if `restoreAll()` is ever called for a different purpose (e.g., entering a "paused" mode), you'd have a zombie scanner.

### 7. `scheduleAutoHide` can race with user interaction

**File:** `MenuBarController.swift:69-81`

```swift
private func scheduleAutoHide() {
    cancelAutoHide()
    let delay = preferences.autoHideDelay
    autoHideTask = Task {
        do {
            try await Task.sleep(for: .seconds(delay))
        } catch {
            return
        }
        isBarredBarVisible = false
        hideSection()
    }
}
```

The `catch` handles cancellation correctly. But between the sleep completing and `hideSection()` executing, the user could have toggled the bar open again. Since this is all on `@MainActor`, interleaving is unlikely in practice, but the logic doesn't verify that `isBarredBarVisible` is still true before hiding. A defensive check costs nothing:

```swift
guard isBarredBarVisible else { return }
```

---

## Edge cases

### 8. No handling of accessibility permission revocation

**Files:** `AccessibilityService.swift`, `BarredApp.swift`

`checkTrust()` is called on init and on status item click. If the user grants permission, uses the app for days, then revokes it in System Settings, the app continues to call `enumerateAllExtrasItems()` which silently returns stale/empty data. The detector keeps "detecting" via the window list fallback with no titles, and the UI gives no indication that something changed.

**Recommendation:** Poll `AXIsProcessTrusted()` on each scan cycle (it's a cheap syscall), or listen for `com.apple.accessibility.api` distributed notifications.

### 9. Item IDs and persistence keys are unstable across restarts

**Files:** `MenuBarItem.swift:5`, `MenuBarDetector.swift:74`

```swift
id: "\(axItem.pid)-\(axItem.indexInApp)"
```

PIDs change every app launch. `indexInApp` can change if the target app adds/removes a menu bar extra. This means:

- SwiftUI's `ForEach` diff treats every item as new after any target app restart, causing unnecessary view rebuilds and potential flicker
- Any future persistence of "hide this item" preferences keyed on `persistenceKey` will break for apps without a `bundleIdentifier` (falls back to PID)

**Why this matters for juniors:** Identity is the most important property of any item in a list. If identity isn't stable, diffing algorithms (SwiftUI, React, etc.) fall apart. The correct key for a menu bar item is `bundleIdentifier + title` (or `bundleIdentifier + index` for untitled items). PID should never be part of a stable identifier.

### 10. `deduplicateAcrossScreens` assumes primary screen items have x >= 0

**File:** `MenuBarDetector.swift:184-186`

```swift
let aOnPrimary = a.frame.origin.x >= 0
let bOnPrimary = b.frame.origin.x >= 0
```

On multi-monitor setups where the secondary display is to the left of the primary, the primary display's coordinate origin is at `(0, 0)` but the secondary display has *negative* x values. However, if the arrangement is different — e.g., the primary is on the right — primary screen items can have *large positive* x values while secondary items are at smaller positive values.

The heuristic "x >= 0 means primary" is simply wrong for many setups. The correct approach is to check which `NSScreen` each item's frame falls within:

```swift
let primaryFrame = NSScreen.main?.frame ?? .zero
let aOnPrimary = primaryFrame.contains(CGPoint(x: a.frame.origin.x, y: a.frame.origin.y))
```

### 11. Expanded divider cap of 10,000px may be insufficient for ultrawide

**File:** `SectionDivider.swift:22`

```swift
return min(screenWidth * 2, 10000)
```

A 49" ultrawide (like the Samsung Odyssey G9) has a native resolution of 5120px. With `2x`, that's 10240px — already exceeding the 10,000 cap. The divider won't fully push items off-screen.

The comment says the cap "avoids the memory leak that occurs with extremely large values." If there's a real memory leak at large values, that needs to be documented with a reference (which macOS version? what threshold?). Otherwise, the cap is cargo-culted caution.

### 12. `appIcon` is computed every time the view renders

**File:** `MenuBarItem.swift:37-43`

```swift
var appIcon: NSImage? {
    guard let bundleIdentifier else { return nil }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.icon
}
```

This is a computed property that does filesystem lookups and process queries. It's called from `MenuBarItemRow`'s `body`, which means every SwiftUI render triggers disk I/O. For a list of 20+ items being scanned every 3 seconds, this adds up.

**Why this matters for juniors:** Computed properties should be cheap. If they do I/O or allocations, they should be cached. Either make `appIcon` a stored `let` populated at creation time, or cache the result with `NSCache`.

### 13. `CGWindowListCopyWindowInfo` deprecation

**File:** `MenuBarDetector.swift:104`

`CGWindowListCopyWindowInfo` is deprecated as of macOS 15. Apple is moving toward `ScreenCaptureKit` for window enumeration. The fallback detection path and the window-ID matching both depend on this API. Plan a migration path.

---

## SwiftUI issues

### 14. Deprecated `tabItem` API

**File:** `SettingsView.swift:8-27`

The `tabItem` modifier is deprecated in favor of the `Tab` type:

```swift
// Current (deprecated)
TabView {
    ItemsSettingsView().tabItem { Label("Menu bar items", systemImage: "menubar.rectangle") }
}

// Preferred
TabView {
    Tab("Menu bar items", systemImage: "menubar.rectangle") {
        ItemsSettingsView()
    }
}
```

### 15. Slider range (1...15) doesn't match model range (1...60)

**File:** `SettingsView.swift:121-126` vs `UserPreferences.swift:20`

The slider restricts input to 1-15 seconds, but the model allows up to 60 on decode. If a user had a persisted value of 30 from a previous version (or manual plist edit), the slider would clamp it to 15 on first interaction — silently losing their preference. Either match the ranges or add a migration.

### 16. Missing keyboard shortcuts

The popover has no keyboard shortcut for toggling the bar, opening settings, or quitting. A menu bar utility that requires mouse interaction for every operation is frustrating for power users. At minimum, the popover should respond to keyboard navigation, and ideally there should be a global hotkey for toggle.

### 17. Re-injecting `@Environment` to child views unnecessarily

**File:** `SettingsView.swift:10-17`

```swift
ItemsSettingsView()
    .environment(controller)
```

The `controller` is already in the environment (injected at the `SettingsView` level from `BarredApp.swift:85`). Explicitly re-injecting it into child views is redundant — `@Environment` propagates down automatically. This suggests confusion about how environment values work.

**Why this matters for juniors:** `@Environment` is inherited. You inject at the root and every descendant can read it. Re-injecting is harmless but noisy — it makes readers think "is this a *different* controller?" and obscures the actual injection point.

---

## Testing

### 18. Test coverage is thin and avoids all hard-to-test code

**Files:** `Tests/BarredTests/`

Current test coverage:
- `MenuBarItemTests` (7 tests) — display name, subtitle, persistence key, equality
- `UserPreferencesTests` (3 tests) — defaults, encoding, partial decode
- `UserPreferencesClampingTests` (3 tests) — boundary validation
- `PreferencesStoreTests` (2 tests) — default init, auto-save
- `AccessibilityServiceTests` (2 tests) — trust check, enumerate-when-untrusted
- `SectionDividerTests` (3 tests) — initial state, pre-setUp no-ops

Not tested at all:
- `MenuBarController` — the entire coordination layer
- `MenuBarDetector.scan()` — the core detection logic, deduplication, window matching
- `SectionDivider.expand()`/`collapse()` with a real status item
- Any view rendering or interaction
- The `showBarredBarOnClick` preference actually doing anything (it doesn't — see #2)

**Why this matters for juniors:** Test coverage isn't about hitting a percentage. It's about testing the code most likely to break. Pure data model tests are the *easiest* to write and the *least likely* to catch real bugs. The business logic in `MenuBarController` and `MenuBarDetector` is where bugs will actually live. The lack of protocols (issue #1) makes this hard — which is why testable architecture matters.

### 19. `SectionDividerTests` only test the nil-statusItem path

**File:** `Tests/BarredTests/SectionDividerTests.swift`

All three tests exercise the early-return path where `statusItem` is nil (setUp hasn't been called). The actual expand/collapse behavior — the entire purpose of the class — is untested. This is like testing a car's ignition by verifying it doesn't start without a key, and then shipping without ever testing that it *does* start with a key.

### 20. `AccessibilityServiceTests` are not really testing behavior

The two tests verify: (a) `checkTrust()` doesn't crash, and (b) enumerate returns empty when untrusted. These pass trivially. There's no test for the actual enumeration logic, the app-filtering heuristic, or what happens when AX returns unexpected data.

---

## Code hygiene

### 21. `#selector` across class boundaries — fragile coupling

**Files:** `SectionDivider.swift:38`, `BarredApp.swift:64`

```swift
// SectionDivider.swift
button.action = #selector(AppDelegate.toggleBarredBarFromDivider)

// BarredApp.swift — must be non-private for selector to resolve
@objc func toggleBarredBarFromDivider() { ... }
```

The divider button sends its action up the responder chain with no target (nil target), hoping `AppDelegate` is there to catch it. This works but is invisible — there's no compile-time guarantee the method exists on the responder chain, and `toggleBarredBarFromDivider` can't be `private` because of it.

**Recommendation:** Pass a callback closure when creating the divider, or use a delegate protocol:

```swift
func setUp(onToggle: @escaping () -> Void)
```

### 22. `quitApp()` is dead code

**File:** `BarredApp.swift:68-71`

```swift
private func quitApp() {
    controller.restoreAll()
    NSApp.terminate(nil)
}
```

This private method is never called. Quitting happens via the popover button (`BarredMenuView.swift:46-48`) which calls `controller.restoreAll()` + `NSApp.terminate(nil)` directly, and via `applicationWillTerminate` for cleanup. Delete it.

### 23. `Barred.entitlements` is empty

**File:** `Resources/Barred.entitlements`

The entitlements file exists and is referenced in code signing, but contains no entries. This isn't wrong — accessibility is an OS-level permission, not an entitlement — but it's confusing. Either add a comment explaining why it's empty, or remove it and drop the `--entitlements` flag from the build script.

### 24. Build script doesn't fail on signing verification failure

**File:** `Scripts/build-app.sh:90`

```bash
spctl --assess --type execute --verbose "$APP_BUNDLE" || echo "  (spctl check may fail...)"
```

The `|| echo` swallows a real failure. If signing fails to meet Gatekeeper requirements, the build continues and produces a zip that users will have to right-click-open. This should be a hard failure in CI (where signing credentials are present) and a soft warning only in local dev.

---

## Summary — prioritized

| Priority | Issue | Impact |
|----------|-------|--------|
| **Critical** | #1 — No protocol abstractions | Blocks testability, previews, and substitution |
| **Critical** | #2 — `showBarredBarOnClick` preference does nothing | Broken feature visible to users |
| **Critical** | #18 — Business logic has zero test coverage | No safety net for the code most likely to break |
| **High** | #8 — No AX permission revocation handling | Silent degradation at runtime |
| **High** | #5 — Hardcoded 1s sleep for synchronization | Race condition on slow machines |
| **High** | #4 — Two build systems (SPM vs Xcode) | CI tests one thing, release ships another |
| **High** | #9 — Unstable IDs based on PID | Persistence and SwiftUI diffing break across restarts |
| **High** | #13 — `CGWindowListCopyWindowInfo` deprecated | Core detection API removed in future macOS |
| **Medium** | #3 — `OverlayWindow.swift` dead code | Cognitive overhead, wasted binary size |
| **Medium** | #10 — Deduplication multi-monitor heuristic is wrong | Incorrect behavior for many monitor arrangements |
| **Medium** | #12 — `appIcon` does I/O on every render | Performance drag on every 3-second scan |
| **Medium** | #14 — Deprecated `tabItem` API | Will warn on newer Xcode |
| **Medium** | #15 — Slider/model range mismatch | Silently loses preferences outside slider range |
| **Medium** | #7 — Auto-hide race with user toggle | Can hide bar user just opened |
| **Medium** | #11 — Divider cap insufficient for ultrawide | Core feature broken on 5K+ ultrawide |
| **Low** | #17 — Redundant environment re-injection | Confusing but harmless |
| **Low** | #21 — `#selector` across class boundaries | Fragile, prevents encapsulation |
| **Low** | #22, #23 — Dead code (quitApp, empty entitlements) | Cleanup |
| **Low** | #24 — Build script swallows signing failure | Could ship unsigned builds |
| **Low** | #16 — No keyboard shortcuts | Poor power-user experience |

## Where to start

The highest-leverage change remains **introducing protocols for services** (#1). It unblocks:
- Real unit tests for `MenuBarController` and `MenuBarDetector` (#18)
- SwiftUI preview support for all views
- Fixing the `showBarredBarOnClick` bug (#2) with confidence (because you can test it)
- Proper synchronization in `start()` (#5) — inject a detector that signals when its first scan completes

Second priority: **fix or remove the dead `showBarredBarOnClick` feature** (#2). A preference that's visible in settings but does nothing is a trust-destroying bug. Users will toggle it, see nothing change, and question whether the app works at all.

Third: **align build systems** (#4). You shouldn't release what you don't test.
