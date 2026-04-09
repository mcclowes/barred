# Barred — code review

Reviewed: 2026-04-09

---

## Architecture

### 1. `MenuBarController` is a god-object singleton

**Files:** `MenuBarController.swift`, `BarredApp.swift`, `BarredMenuView.swift`, `SettingsView.swift`

`MenuBarController.shared` owns the accessibility service, the detector, the preferences store, the section divider, the auto-hide timer, *and* the toggle state. Every view reaches directly into this singleton. This creates several problems:

- **Untestable.** You cannot inject a mock controller into views or unit tests. The `shared` instance is constructed at import time, which means tests that touch any view will spin up real accessibility queries and timers.
- **Tight coupling.** Views depend on the concrete class rather than a protocol, so you can't swap implementations (e.g. a "preview" controller for SwiftUI previews).
- **Hidden dependencies.** `BarredMenuView` and `SettingsView` both create `@State private var controller = MenuBarController.shared`. This is not `@State` doing useful work — the object is shared mutable state, not view-owned state. It survives across the entire app lifetime via the singleton regardless.

**Recommendation:** Extract a protocol (e.g. `MenuBarControlling`), inject via `@Environment`, and pass the real implementation from the app root. Use a lightweight stub in previews and tests.

```swift
// Before
@State private var controller = MenuBarController.shared

// After — inject from the app root via @Environment
@Environment(MenuBarController.self) private var controller
```

### 2. `@State` used for shared singleton — wrong property wrapper

**Files:** `BarredMenuView.swift:4`, `SettingsView.swift:5`

`@State` is designed for *view-owned, value-type* local state. Using it to hold a reference to a singleton `@Observable` class is misleading. The `@State` wrapper here is effectively a no-op — it doesn't own the lifecycle of the object (the singleton does). This will confuse any engineer who understands what `@State` is supposed to mean.

If you must use a singleton, at minimum store it as a `let` and pass it through the environment. `@State` with a class instance is only appropriate when the view truly *creates and owns* that instance.

### 3. `PreferencesStore` is never saved automatically

**File:** `PreferencesStore.swift`

The store exposes `preferences` as a plain `var` and has a separate `save()` method. Every call site must remember to call `save()` after mutation. This is a classic "forgot to save" bug waiting to happen. In `SettingsView.swift` there are three separate `Binding(get:set:)` blocks, each manually calling `controller.preferencesStore.save()`.

**Recommendation:** Use a `didSet` observer or a Combine/observation-based approach to auto-persist:

```swift
var preferences: UserPreferences {
    didSet { persist() }
}
```

### 4. No dependency injection anywhere

The app has zero protocol abstractions. `AccessibilityService`, `MenuBarDetector`, `PreferencesStore`, `SectionDivider` are all concrete classes instantiated directly. This means:

- You cannot write unit tests for `MenuBarController` without triggering real AX queries
- You cannot write unit tests for `MenuBarDetector` without a running app
- SwiftUI previews are impossible for views that depend on the controller

---

## Concurrency and thread safety

### 5. `Timer.scheduledTimer` inside a `@MainActor` class — use modern concurrency

**File:** `MenuBarDetector.swift:18-22`

```swift
timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
    Task { @MainActor in
        self?.scan()
    }
}
```

This creates a Foundation `Timer`, captures `self` weakly, then hops back to the main actor with `Task { @MainActor in }`. This is the old-world approach. Use `Task` + `Task.sleep(for:)` in a loop:

```swift
// After
private var scanTask: Task<Void, Never>?

func startScanning() {
    scan()
    scanTask = Task {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            scan()
        }
    }
}

func stopScanning() {
    scanTask?.cancel()
    scanTask = nil
}
```

This is cancellable, doesn't require `[weak self]` hacks, and respects structured concurrency.

### 6. `PreferencesStore` is missing `@MainActor`

**File:** `PreferencesStore.swift:3`

```swift
@Observable
final class PreferencesStore {
```

Per Swift concurrency rules and SwiftUI best practices, `@Observable` classes must be marked `@MainActor` unless the project uses MainActor default isolation (which this project does not — `project.yml` uses `SWIFT_STRICT_CONCURRENCY: complete` but not `SWIFT_DEFAULT_ACTOR_ISOLATION`). This is a data race waiting to happen if anything off-main-actor touches this object.

### 7. `scheduleAutoHide` has a subtle race condition

**File:** `MenuBarController.swift:71-80`

```swift
private func scheduleAutoHide() {
    cancelAutoHide()
    let delay = preferences.autoHideDelay
    autoHideTask = Task {
        try? await Task.sleep(for: .seconds(delay))
        guard !Task.isCancelled else { return }
        isBarredBarVisible = false
        hideSection()
    }
}
```

The `try? await Task.sleep` silently swallows `CancellationError`, then the code checks `Task.isCancelled`. But `try?` on the sleep means if the task is cancelled *during* the sleep, execution continues to the guard check, which correctly catches it. However, if cancellation happens between the guard check and `hideSection()`, you'll hide while the user just toggled it open. The window is small but real.

More importantly: the `try?` pattern means any *other* error from `Task.sleep` (theoretically none today, but fragile) would also be silently eaten.

---

## SwiftUI issues

### 8. Three manual `Binding(get:set:)` blocks in `GeneralSettingsView`

**File:** `SettingsView.swift:99-142`

The reference guide explicitly says: *"Strongly prefer to avoid creating bindings using `Binding(get:set:)` in view body code."* Here there are three of them, each performing side effects in the setter. This is fragile and verbose.

```swift
// Before
Toggle("Show Barred bar on click", isOn: Binding(
    get: { controller.preferences.showBarredBarOnClick },
    set: { newValue in
        controller.preferences.showBarredBarOnClick = newValue
        controller.preferencesStore.save()
    }
))

// After — with auto-saving PreferencesStore
@Bindable var controller: MenuBarController
// ...
Toggle("Show Barred bar on click", isOn: $controller.preferences.showBarredBarOnClick)
```

If you fix issue #3 (auto-saving preferences), all three manual bindings collapse to one-liners.

### 9. `tabItem` is deprecated — use `Tab` API

**File:** `SettingsView.swift:8-25`

```swift
// Before
TabView {
    ItemsSettingsView(controller: controller)
        .tabItem {
            Label("Menu bar items", systemImage: "menubar.rectangle")
        }
    // ...
}

// After
TabView {
    Tab("Menu bar items", systemImage: "menubar.rectangle") {
        ItemsSettingsView(controller: controller)
    }
    // ...
}
```

### 10. Computed properties recalculated on every body evaluation

**File:** `SettingsView.swift:31-47`

`visibleItems`, `hiddenItems`, and `appsWithMultipleItems` are all computed properties that filter/group the full detected items array. These are recalculated every time `body` is called. For a menu bar app this is likely fine in practice, but it's a bad habit — especially `appsWithMultipleItems` which builds a `Dictionary`, filters it, then converts to a `Set` on every render.

### 11. `OnboardingView` — decorative image not marked as such

**File:** `OnboardingView.swift:8-9`

```swift
Image(systemName: "lock.shield")
    .font(.system(size: 40))
```

This decorative image will be read by VoiceOver as "lock shield" which is meaningless to the user. Either mark it `accessibilityHidden(true)` or give it a meaningful label.

### 12. `AboutView` — same decorative image issue

**File:** `SettingsView.swift:151-153`

```swift
Image(systemName: "menubar.arrow.up.rectangle")
    .font(.system(size: 48))
```

Same issue — mark decorative images as such for VoiceOver.

### 13. Missing keyboard shortcuts

No keyboard shortcut for toggling the barred bar or quitting. Menu bar apps should support global hotkeys or at least keyboard shortcuts in the popover.

---

## Edge cases and bugs

### 14. `appIcon` crashes on nil `bundleIdentifier`

**File:** `MenuBarItem.swift:39-46`

```swift
var appIcon: NSImage? {
    if let bundleIdentifier,
       let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
    {
        return NSWorkspace.shared.icon(forFile: url.path)
    }
    return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier ?? "").first?.icon
}
```

The fallback passes `""` when `bundleIdentifier` is nil. `runningApplications(withBundleIdentifier: "")` returns an empty array, so this is harmless but misleading — it will *never* find anything. The fallback is dead code masquerading as a real recovery path. Be honest: return `nil`.

### 15. `persistenceKey` is unstable for items without titles

**File:** `MenuBarItem.swift:48-52`

```swift
var persistenceKey: String {
    let bundle = bundleIdentifier ?? "pid-\(pid)"
    let itemTitle = title ?? "item-\(itemIndex)"
    return "\(bundle):\(itemTitle)"
}
```

When `bundleIdentifier` is nil, the key falls back to `pid-\(pid)`. PIDs change every launch. Any persistence based on this key (hiding preferences, etc.) will break across restarts for items without a bundle identifier. Similarly, `itemIndex` can change if the app's menu bar items change order.

### 16. Item `id` is based on PID — changes every app restart

**File:** `MenuBarItem.swift:7`, `MenuBarDetector.swift:72`

```swift
id: "\(axItem.pid)-\(axItem.indexInApp)"
```

`Identifiable.id` is `"\(pid)-\(index)"`. Since PIDs change on every process launch, SwiftUI's `ForEach` will treat every item as new on every scan cycle if the PID changes. This means unnecessary view recreation and potential animation glitches.

### 17. `deduplicateAcrossScreens` assumes primary screen has x >= 0

**File:** `MenuBarDetector.swift:172-191`

```swift
let aOnPrimary = a.frame.origin.x >= 0
```

This assumes the primary screen always has non-negative x-coordinates. On multi-monitor setups where the primary screen isn't the leftmost, secondary screen items can have positive x-coordinates too. The deduplication heuristic could keep the wrong duplicate.

### 18. `expandedLength` cap of 4000px is fragile

**File:** `SectionDivider.swift:17-21`

```swift
private var expandedLength: CGFloat {
    guard let screen = NSScreen.main else { return 2000 }
    let screenWidth = screen.frame.width
    return max(500, min(screenWidth + 200, 4000))
}
```

On a 5K or ultrawide display, `screenWidth + 200` could exceed 4000, meaning the divider doesn't fully push items off-screen. The cap should probably be `screenWidth * 2` or similar, not an arbitrary constant.

### 19. `SectionDivider.setUp` called once — doesn't handle status bar changes

**File:** `SectionDivider.swift:25-41`

If the system menu bar resets (e.g. display reconfiguration, user logs out/in), the divider's status item may be lost or repositioned. There's no recovery logic — the divider is created once in `setUp()` and never checked again.

### 20. No handling of accessibility permission revocation

**Files:** `AccessibilityService.swift`, `BarredApp.swift`

The trust check (`AXIsProcessTrusted()`) is only called on click and at init. If the user revokes accessibility permission while the app is running, the app will continue attempting AX operations that silently fail. There should be a periodic trust check or a `DistributedNotificationCenter` listener for `com.apple.accessibility.api` changes.

### 21. Force casts in AXExtensions

**File:** `AXExtensions.swift:29, 40`

```swift
// swiftlint:disable:next force_cast
let axValue = value as! AXValue
```

These force casts are protected by `CFGetTypeID` checks, but the pattern is fragile. If Apple ever changes the underlying type, this crashes. Use `as?` and return `nil`:

```swift
guard let axValue = value as? AXValue else { return nil }
```

### 22. `scan()` iterates every running application — including background agents

**File:** `AccessibilityService.swift:31-33`

```swift
let apps = NSWorkspace.shared.runningApplications
for app in apps {
```

This iterates *every* running application (often 100+), including background agents, XPC services, and daemons. Most of these have no menu bar extras. Consider filtering to `.activationPolicy == .regular` or `.accessory` first, or at least caching which PIDs have extras so you don't re-query empty ones every 3 seconds.

### 23. `menuBarWindowMap` magic number: layer 25

**File:** `MenuBarDetector.swift:103`

```swift
layer == 25
```

Window layer 25 is the status item layer, but this is undocumented and could change across macOS versions. At minimum, define this as a named constant with a comment explaining its source.

### 24. Width guard of `width < 200` silently drops wide items

**File:** `MenuBarDetector.swift:115`

```swift
guard width > 0, width < 200, height > 0 else { return nil }
```

Some menu bar items (e.g. iStat Menus, music now-playing widgets) can be wider than 200px. This silently drops them from detection.

---

## Testing

### 25. Only 2 test files, covering only data models

**Files:** `Tests/BarredTests/`

There are only tests for `MenuBarItem` and `UserPreferences` — both pure data structs. Zero tests for:

- `MenuBarController` (all business logic)
- `MenuBarDetector` (core detection logic)
- `PreferencesStore` (persistence)
- `SectionDivider` (the core mechanism of the app)
- `AccessibilityService` (even the trust-check logic)
- Any views

The lack of protocol abstractions (issue #4) makes this hard to fix, which is the real problem. The architecture should be designed for testability from the start.

### 26. No test for `UserPreferences` clamping

**File:** `UserPreferences.swift:20`

```swift
autoHideDelay = min(60.0, max(1.0, try container.decodeIfPresent(...) ?? 5.0))
```

There's a clamping guard on decode (1.0–60.0), but no test verifies it. What happens when someone manually edits the plist to set `autoHideDelay: -5`? Or `999`? The tests only cover the happy path.

---

## Code hygiene

### 27. `print()` statements in production code

**Files:** `SectionDivider.swift:48,52,69`, `MenuBarDetector.swift:42-47`

The `SectionDivider` has unconditional `print()` calls (not gated by `#if DEBUG`). These will appear in Console.app for end users and pollute their logs. Either remove them or gate behind `#if DEBUG`.

```swift
// SectionDivider.swift:48 — NOT gated by #if DEBUG
print("[Barred] expand() skipped — statusItem is nil (setUp not called yet?)")
```

### 28. `#selector(AppDelegate.toggleBarredBarFromDivider)` — cross-class selector

**File:** `SectionDivider.swift:36`

The divider reaches across to `AppDelegate` via a selector string. This is fragile — if `toggleBarredBarFromDivider` is renamed or removed, there's no compile-time error. Consider passing a closure or delegate instead.

### 29. `toggleBarredBarFromDivider` is not private

**File:** `BarredApp.swift:65`

```swift
@objc func toggleBarredBarFromDivider() {
```

This is `internal` (default access) when it should be `@objc private` or at least documented as to *why* it's public — it's only public because the selector needs to find it, but this could be solved with a proper delegate pattern.

### 30. Redundant imports

**File:** `MenuBarDetector.swift:1-4`

```swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
```

`AppKit` re-exports `Foundation` and `CoreGraphics`. `ApplicationServices` is needed for `AXUIElement`, but the other three can be collapsed to `import AppKit` + `import ApplicationServices`.

### 31. `NSApp.activate()` is deprecated

**File:** `BarredApp.swift:87`

```swift
.onAppear {
    NSApp.activate()
}
```

`NSApplication.activate()` without parameters is deprecated in macOS 14+. Use `NSApp.activate(ignoringOtherApps: true)` or better yet, `NSApp.activate()` is unnecessary if the window is already key and ordered front.

---

## Summary — prioritized

| Priority | Issue | Impact |
|----------|-------|--------|
| **Critical** | #1, #4 — Singleton god-object, no DI | Blocks all testability and preview support |
| **Critical** | #25 — Near-zero test coverage of business logic | No safety net for regressions |
| **High** | #6 — `PreferencesStore` missing `@MainActor` | Potential data race under strict concurrency |
| **High** | #3, #8 — Manual save + manual bindings | Bug-prone boilerplate that will accumulate |
| **High** | #20 — No handling of AX permission revocation | Silent failure at runtime |
| **High** | #22 — Scanning all 100+ processes every 3s | Unnecessary CPU/AX overhead |
| **Medium** | #5 — Foundation Timer instead of async/await | Outdated concurrency pattern |
| **Medium** | #9 — Deprecated `tabItem` API | Will generate warnings on newer Xcode |
| **Medium** | #15, #16 — Unstable IDs based on PID | Persistence breaks across restarts |
| **Medium** | #18 — Expanded length cap too low for ultrawide | Core feature broken on large displays |
| **Medium** | #27 — print() in production code | Noise in user logs |
| **Low** | #11, #12 — Decorative images not hidden from VoiceOver | Accessibility clutter |
| **Low** | #23, #24 — Magic numbers | Maintainability debt |
| **Low** | #30 — Redundant imports | Cleanliness |

The single highest-leverage change is **breaking the singleton and introducing protocols** (#1, #4). Almost every other issue — testability, view previews, manual bindings — cascades from the current architecture. Fix the foundation first.
