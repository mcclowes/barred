# Barred — holistic code review

**Reviewer:** Principal engineer, fresh eyes, onboarding
**Date:** 2026-04-10
**Scope:** `Sources/Barred/**`, `Tests/BarredTests/**`, `project.yml`, `Makefile`
**Audience:** Team members at all levels — flagged with *(learning note)* where there is a broader engineering lesson worth internalising.

> This review is deliberately blunt. "Brownfield" doesn't mean "bad" — the codebase is small, compiles under strict concurrency, and has tests. But several foundations need reworking before this app can grow, and a few issues are correctness bugs in disguise. Existing fixes in `CODE_REVIEW.md` are not re-raised here.

---

## TL;DR (top 10 things to fix, highest impact first)

| # | Severity | Area | Summary |
|---|----------|------|---------|
| 1 | **🔴 Critical** | `MenuBarDetector.waitForFirstScan` | Single-slot continuation leaks and deadlocks on concurrent callers. |
| 2 | **🔴 Critical** | `AccessibilityService.enumerateAllExtrasItems` | Synchronous, unbounded AX IPC on the main actor — any unresponsive app hangs the whole UI. No `AXUIElementSetMessagingTimeout`. |
| 3 | **🔴 Critical** | `SettingsView` launch-at-login toggle | Revert-on-error path re-triggers `onChange` → potential infinite loop; errors are silently swallowed. |
| 4 | 🟠 High | `MenuBarDetector` polling loop | 3-second wall-clock polling prevents App Nap, wastes battery, and is the wrong architecture — should be notification-driven. |
| 5 | 🟠 High | `MenuBarItem.isHidden` | `frame.origin.x < 0` is a coordinate-space bug on multi-monitor layouts where the primary isn't at x=0. |
| 6 | 🟠 High | `PreferencesStore` | Swallows encode/decode errors; tests pollute `UserDefaults.standard`; not injectable. |
| 7 | 🟠 High | `MenuBarController` | Calls `detector.startScanning()` in `init` — hidden side effect, bad for testing and lifecycle control. |
| 8 | 🟡 Medium | `SectionDivider.expandedLength` | Uses `NSScreen.main` (key-window screen, not primary) and never reacts to screen changes. |
| 9 | 🟡 Medium | `MenuBarItem` identity | `itemIndex` comes from unstable enumeration order → `persistenceKey` churn → flickering SwiftUI rows. |
| 10 | 🟡 Medium | `BarredMenuView` | Uses `.buttonStyle(.plain)` on what pretends to be a menu; no keyboard navigation, no hover, inaccessible to VoiceOver as a menu. |

Everything else below is worth fixing but doesn't gate shipping.

---

## 1. Concurrency & correctness bugs

### 1.1 🔴 `waitForFirstScan` is a single-use continuation with no reentrancy protection

`Sources/Barred/Services/MenuBarDetector.swift:29-34`

```swift
func waitForFirstScan() async {
    if hasCompletedFirstScan { return }
    await withCheckedContinuation { continuation in
        firstScanContinuation = continuation
    }
}
```

Three concrete failure modes:

1. **Lost wakeup.** If two callers await this *before* the first scan completes, the second `continuation` assignment overwrites the first. The first continuation is dropped on the floor and *never resumes* — its awaiter hangs forever. `CheckedContinuation` will actively log a leak at runtime but it will not crash in release.
2. **Double-resume.** If `scan()` runs twice before `hasCompletedFirstScan` is observed (remember — `scan()` is public and can be called externally *while* `startScanning()`'s internal scan is in flight), the `firstScanContinuation?.resume()` call can fire twice. `CheckedContinuation` traps on double-resume → crash.
3. **`scan()` has interior `await` points.** It's `@MainActor` but not re-entrancy-safe. Two overlapping scan invocations can clobber `detectedItems` mid-update and race the "first scan" bookkeeping.

**Fix (two-part):**

```swift
// Use an AsyncStream or a private "first-scan" Task<Void, Never> that
// multiple callers can await independently.
private let firstScanTask: Task<Void, Never>

// Alternatively, since there are only a few call sites, gate scan() with
// an actor or an in-flight flag.
```

Minimum viable fix — store an array of continuations:

```swift
private var firstScanWaiters: [CheckedContinuation<Void, Never>] = []

func waitForFirstScan() async {
    if hasCompletedFirstScan { return }
    await withCheckedContinuation { firstScanWaiters.append($0) }
}

// On completion, drain:
if !hasCompletedFirstScan {
    hasCompletedFirstScan = true
    firstScanWaiters.forEach { $0.resume() }
    firstScanWaiters.removeAll()
}
```

Better yet, expose this as a cached `Task<Void, Never>`:

```swift
private lazy var firstScan: Task<Void, Never> = Task { await self.scan() }
func waitForFirstScan() async { await firstScan.value }
```

Now any number of awaiters are correct, and scanning the first time is done exactly once.

*(Learning note):* `CheckedContinuation` is a **one-shot** primitive. If the code shape suggests "what if two things await this at once?" — it's the wrong primitive. Reach for `AsyncStream`, `Task<Value, Never>`, or an actor. Never store a bare continuation in a mutable field without explicit "only one waiter allowed" invariants.

---

### 1.2 🔴 `scan()` is not re-entrancy-safe

Same file, `scan()` line 55. It's `public`, `@MainActor`, and calls `await fetchStatusItemWindows()` which suspends. While suspended, an external caller can invoke `scan()` again. Both will update `detectedItems`, both will check `hasCompletedFirstScan`, and (per §1.1) both can try to resume the first-scan continuation.

**Fix:** either make `scan()` private and expose only `forceRescan()` which enqueues onto a serial task, or guard it with:

```swift
private var scanInFlight = false

func scan() async {
    guard !scanInFlight else { return }
    scanInFlight = true
    defer { scanInFlight = false }
    // ...
}
```

Tests call `await detector.scan()` directly (good), so they'd start hitting this guard — rewrite tests to use a single scan invocation per test.

---

### 1.3 🔴 AX calls block the main actor with no timeout

`Sources/Barred/Services/AccessibilityService.swift:34-74`

`enumerateAllExtrasItems()` is `@MainActor` and calls, for every running app:

- `AXUIElementCreateApplication(pid)` — cheap
- `axApp.attribute("AXExtrasMenuBar")` — IPC to the target process
- `extrasMenuBar.children()` — another IPC
- For each child: `title()`, `description_()`, `identifier()`, `frame()` → **up to 4 more round trips per item**

With ~20 apps × 3 items each, that's ~260 synchronous IPC calls on the main thread. Each `AXUIElementCopyAttributeValue` can block *for seconds* if the target process is unresponsive (stuck in GCD, waiting on a lock, mid-launch, crashing). When that happens, **your whole UI freezes**, the menu bar stops responding, and the user blames macOS.

There is a fix that is one line per `AXUIElement` creation:

```swift
let axApp = AXUIElementCreateApplication(app.processIdentifier)
AXUIElementSetMessagingTimeout(axApp, 0.5) // seconds — anything unresponsive returns early
```

Additionally:

- Move the whole enumeration *off* the main actor onto a background task. `AXUIElement` operations are thread-safe. Only the UI update must hop back to `@MainActor`. Today you're paying main-thread latency for ~260 IPCs every 3 seconds. That is *why* the app feels heavy.
- Bundle the four per-item attribute reads into a single `AXUIElementCopyMultipleAttributeValues` call — it's an order of magnitude faster because it's one IPC round trip instead of four.
- Skip reading `description`/`identifier` unless `title` is nil — three of the four reads are dead weight when the common case (named item) is hit.

*(Learning note):* **IPC is not a function call.** When you cross a process boundary, assume latency measured in milliseconds and failure rates that are non-zero. Strict-concurrency `@MainActor` protects you from threads racing, not from IPC blocking. Always set timeouts on external calls and always move them off the main actor.

---

### 1.4 🔴 Launch-at-login toggle can infinite-loop

`Sources/Barred/Views/SettingsView.swift:101-112`

```swift
Toggle("Launch at login", isOn: $controller.preferences.launchAtLogin)
    .onChange(of: controller.preferences.launchAtLogin) { _, newValue in
        do {
            if newValue { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            controller.preferences.launchAtLogin = !newValue
        }
    }
```

Walk through the failure path:

1. User toggles ON → `newValue=true` → `register()` throws.
2. `catch` sets `launchAtLogin = false`.
3. `onChange` re-fires with `newValue = false` → calls `unregister()`.
4. If `unregister()` also throws (very possible: there's nothing registered), we set `launchAtLogin = true`.
5. Go to step 1.

Even when it *doesn't* loop, it makes an extra, wrong-direction API call every time `register()` fails, and the user gets zero feedback: the toggle just flicks back with no alert, no log, no indication of *why*.

**Fix:**

```swift
@State private var isUpdatingLaunchAtLogin = false
@State private var launchAtLoginError: String?

Toggle("Launch at login", isOn: $controller.preferences.launchAtLogin)
    .onChange(of: controller.preferences.launchAtLogin) { oldValue, newValue in
        guard !isUpdatingLaunchAtLogin else { return } // break the loop
        isUpdatingLaunchAtLogin = true
        defer { isUpdatingLaunchAtLogin = false }
        do {
            try newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            launchAtLoginError = error.localizedDescription
            controller.preferences.launchAtLogin = oldValue
        }
    }
    .alert("Couldn't update Login Items", isPresented: .constant(launchAtLoginError != nil)) {
        Button("OK") { launchAtLoginError = nil }
    } message: {
        Text(launchAtLoginError ?? "")
    }
```

Better still: don't model `launchAtLogin` as a preference at all. The source of truth is `SMAppService.mainApp.status`. Reflect that status directly and drop the `UserPreferences` field. The current design invites desync: a user can edit the JSON preferences file by hand and Barred has no way to reconcile.

*(Learning note):* **Reverting state inside an `onChange` handler for the same state is a red flag.** Any time you do `state = !newValue` inside `.onChange(of: state)` you should be asking "what prevents this from re-entering?" — and "I don't know" means you have a bug.

---

### 1.5 🟠 `scanTask` loop polls every 3 seconds forever

`MenuBarDetector.swift:36-48`

```swift
scanTask = Task {
    await scan()
    while !Task.isCancelled {
        try await Task.sleep(for: .seconds(3))
        await scan()
    }
}
```

Every three seconds, this:

- Hits SCShareableContent (another IPC).
- Walks every `NSRunningApplication`.
- Issues dozens of AX IPC calls (§1.3).
- Updates an `@Observable` → SwiftUI diffs the menu bar list.

On a MacBook idling, this prevents App Nap, keeps the CPU warm, and churns the SwiftUI graph. For a menu bar app that ships on everyone's Mac, this is a meaningful battery regression.

The correct architecture is **event-driven**:

- `NSWorkspace.shared.notificationCenter` provides `didLaunchApplicationNotification` and `didTerminateApplicationNotification`. That handles 90% of churn.
- For in-app menu-extra creation (less common), observe via an `AXObserver` on each relevant app — this is explicitly what the AX API is for.
- Do an immediate scan on wake (`NSWorkspace.didWakeNotification`) and on screen changes (`NSApplication.didChangeScreenParametersNotification`) — two paths where events fire unreliably.
- Keep a long throttle (e.g. 60s) for a safety-net scan rather than 3s polling.

This is a larger refactor but directly addresses the "why does my battery tank?" complaint you *will* get once shipped.

---

## 2. Architecture & design

### 2.1 🟠 `MenuBarController.init` has hidden side effects

`Sources/Barred/Services/MenuBarController.swift:24-35`

```swift
init(...) {
    ...
    self.detector = detector ?? MenuBarDetector(accessibilityService: accessibilityService)
    self.detector.startScanning() // ← initializer launches a background Task
}
```

Constructors should construct. Launching tasks, setting up observers, mutating external state — all of that belongs in an explicit lifecycle method (`start()`, which already exists). Today:

- Tests that inject a `MockDetector` have scanning kicked off silently (`MockDetector.scanningStarted = true`) as a side effect of construction. This gives the illusion of mockability without giving you control of lifecycle.
- The controller starts scanning even if `AppDelegate.start()` is never reached — e.g. during a SwiftUI preview or a test that only instantiates the controller to verify `initialState`. Today that test (`MenuBarControllerTests.initialState`) fires up a background poll loop on the real detector every time it runs in other harnesses. You're getting away with it because of the mock.

**Fix:** Move `detector.startScanning()` into `start()`. Tests that want scanning call `start()` explicitly. Default arguments in init should be *dumb* (no external state).

*(Learning note):* **Think hard before a constructor does anything other than assign fields.** If your tests need to "undo" construction, construction is doing too much. If your SwiftUI previews trigger timers or network calls just by instantiating a view model, you have the same bug.

---

### 2.2 🟠 Default-argument DI is hiding the real composition root

`MenuBarController.init` takes four protocol parameters, each with a concrete default. That means:

- Reading the init signature tells you nothing about what the app actually uses in production.
- If you ever want two controllers (say, one for the real app, one for diagnostics) they silently share none of their dependencies.
- The file depends on every concrete type it claims to abstract — the protocols add zero decoupling at the module level.

**Fix:** force construction in `AppDelegate`. No defaults. If you want a test-friendly constructor, give tests a convenience `TestController.make(...)` factory that supplies mocks. Real DI is explicit; defaults are for convenience, not for architecture.

*(Learning note):* **Protocols with only-ever-one-implementation are not abstractions, they are taxes.** Use them only when (a) you have a real second implementation, usually a mock, **and** (b) the seam reduces coupling in a measurable way. Here the seam is worthwhile for testing, but the *composition* should happen in one place — the app entry point.

---

### 2.3 🟡 `AXUIElement` stored on `MenuBarItem` is (apparently) dead

`MenuBarItem.axElement: AXUIElement?` — I can't find a caller that uses it. If the intent is to later invoke menu extras via `performAction(kAXPressAction)`, fine — document that and add a test. If not, delete it. Dead fields age into "nobody remembers why it's there" within weeks and then block refactors.

More importantly: `AXUIElement` is a CF type that holds an IPC handle to another process. Storing one per row means if that process dies, you've got a stale handle sitting in your model. Prefer re-looking-up the element on demand.

---

### 2.4 🟡 `MenuBarItem.id` / `persistenceKey` churn on unstable ordering

`MenuBarItem.init` builds `id` as `"\(bundle):\(itemTitle)"` where `itemTitle = title ?? "item-\(itemIndex)"`. For items without a title, the ID is entirely dependent on `itemIndex`, which comes from the enumeration order of `NSWorkspace.runningApplications` and `AXUIElement.children()`. Neither of those is stable across calls:

- Apps can re-order in `runningApplications` as they gain/lose focus.
- AX children order can change when the app adds/removes items.

So **every scan can change the IDs of nameless items**. SwiftUI then treats them as brand-new rows, destroying and recreating views, losing scroll position and animation identity.

**Fix options:**

- Use a stable sort key (e.g. AX frame x-position, or first-seen order cached in a `[String: UUID]` map keyed by a hash of reproducible-per-item attributes).
- For truly anonymous items, accept that they cannot be persisted and mark them as such instead of fabricating an index.

---

### 2.5 🟡 `MenuBarItem.isHidden` is broken for multi-monitor layouts

```swift
var isHidden: Bool { frame.origin.x < 0 }
```

macOS screen coordinates are per-display. If the user has a secondary monitor positioned to the left of the primary, its x values are negative and every status item *on that screen* reports `isHidden == true`. Conversely, items pushed off-screen by the divider on the secondary monitor may still be at x > 0.

**Fix:** compute "hidden" as "not contained by the union of all screens' frames" *or* "origin.x lies outside the owning screen's visible frame":

```swift
var isHidden: Bool {
    !NSScreen.screens.contains { $0.frame.contains(frame.origin) }
}
```

This is a *correctness* bug, not a style issue. It surfaces directly in the Settings UI as items appearing in the wrong section.

---

### 2.6 🟡 `SectionDivider.expandedLength` uses `NSScreen.main`, not the primary

```swift
guard let screen = NSScreen.main else { return 2000 }
```

`NSScreen.main` is the screen with the current key window, not the primary. If the user's frontmost window is on a secondary monitor, this computes a width based on *that* screen, which may be smaller than the primary where the menu bar actually is. Use `NSScreen.screens.first` (primary — the one with the menu bar on stock configurations) or iterate all screens and take the widest.

Also: never react to `NSApplication.didChangeScreenParametersNotification`. Plug/unplug a monitor while the divider is expanded and it's now stale. Observe that notification and re-apply `length` when currently expanded.

---

### 2.7 🟡 Divider "push items off-screen" strategy has no failure detection

The whole visible-vs-hidden mechanism depends on Apple honouring an arbitrarily large `NSStatusItem.length`. Dozer and Hidden Bar do the same thing, and this works — until it doesn't. macOS Sequoia tightened several status-bar behaviours and this is the kind of thing Apple silently breaks in a point release.

Add a sanity check: after setting `statusItem.length = length`, compare `statusItem.length` (or better, `button.window?.frame.width`) to the requested value. If it doesn't match, log and degrade gracefully — maybe fall back to a `Menu` that lets the user pick items explicitly.

Also: the `SectionDivider.setUp` docstring says "Must be called AFTER the main Barred status item exists, so the divider appears to its left." — but nothing enforces that ordering programmatically. A future refactor in `AppDelegate` that creates the divider first will silently break the whole product. Add a runtime assertion or — better — invert the dependency: let the controller own the status-item registration order.

---

## 3. Data & state management

### 3.1 🟠 `PreferencesStore` swallows errors silently

```swift
init() {
    if let data = UserDefaults.standard.data(forKey: Self.key),
       let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
        preferences = decoded
    } else {
        preferences = UserPreferences()
    }
}

private func persist() {
    if let data = try? JSONEncoder().encode(preferences) {
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
```

Three bugs hiding in nine lines:

1. **Decode failure silently resets preferences.** If the encoding schema changes (e.g. a new mandatory field) or the user edits defaults manually, the next launch wipes their settings without telling them.
2. **Decode failure doesn't clear the bad blob.** On the next persist, the bad data is overwritten — good. But between launches, it keeps failing every time, and your logs show nothing.
3. **Encode failure silently drops writes.** This is nearly impossible for a well-formed `Codable` struct, but swallowing it means you'll never find out if it ever happens.

**Fix:** log via `os.Logger` at `.error` level in both paths, and on decode failure back up the bad blob to a sidecar key so support can recover it.

### 3.2 🟠 `PreferencesStoreTests` mutates real `UserDefaults.standard`

```swift
let key = "com.barred.preferences"
let saved = UserDefaults.standard.data(forKey: key)
UserDefaults.standard.removeObject(forKey: key)
// ... test ...
if let saved { UserDefaults.standard.set(saved, forKey: key) }
```

This is the "save/restore" pattern, which is wrong for three reasons:

1. **Parallelism.** Swift Testing runs tests concurrently by default. Two tests touching `UserDefaults.standard["com.barred.preferences"]` at the same time will interfere.
2. **Crash leaks state.** If the test body crashes before the restore block runs, the user's real preferences are permanently nuked.
3. **Test order dependency.** The "default init" test assumes no data exists, but running it after "autoSave" means data is there. The test save/restores against `saved` snapshotted *at the start*, so it works by accident, but the coupling is fragile.

**Fix:** make `PreferencesStore` take a `UserDefaults` dependency in init:

```swift
init(defaults: UserDefaults = .standard) { ... }
```

Then tests use `UserDefaults(suiteName: "test-\(UUID())")!`, which is genuinely isolated and auto-cleaned.

*(Learning note):* **Any test that mutates a global singleton is a bad test.** It is a bug waiting for a parallel test runner (which Swift Testing *is*) to expose it. The fix is almost always dependency injection.

### 3.3 🟡 `UserPreferences.init(from:)` silently clamps and loses information

Decoding `autoHideDelay` clamps to `[1, 15]`. This is user-data-mutation during decode — if the on-disk value is 30 and we decode, mutate something unrelated, and re-save, the user's 30 is gone forever. At minimum: clamp only on *read*, not during decode. Better: leave the struct schema permissive and do the clamp in the UI (slider range already enforces `1...15`).

### 3.4 🟡 `PreferencesStore.key = "com.barred.preferences"` doesn't match bundle ID

The bundle ID is `com.mcclowes.barred`; the preferences key is `com.barred.preferences`. Two namespaces for the same product. Not a bug today but a gotcha in tooling/scripts that grep UserDefaults by bundle ID.

---

## 4. UI / UX / Accessibility

### 4.1 🟡 `BarredMenuView` is a `VStack` pretending to be a menu

```swift
VStack(alignment: .leading, spacing: 8) {
    Button(...) {...}.buttonStyle(.plain)
    Divider()
    ...
}
```

Problems:

- **`.buttonStyle(.plain)` kills hover highlighting.** Users have no visual confirmation of what's clickable. macOS popovers that replace menus should highlight rows.
- **Not keyboard navigable.** You can't arrow through it, you can't `↩` to activate. For a menu bar app, that's failing HIG.
- **`VStack` with hardcoded `.frame(width: 240)`** breaks with Dynamic Type. Enlarge text at the OS level and the strings truncate.
- **No `.accessibilityLabel`** on the icon-plus-text buttons — VoiceOver reads "Button", then both strings in sequence, redundantly. `Button("Show Barred bar", systemImage: "eye")` is already the right pattern; but `.buttonStyle(.plain)` hides the button affordance from VoiceOver.

**Fix:** use `NSMenu` for the popover content. This is a stock macOS menu — the system handles hover, keyboard navigation, and accessibility. For the "⌘+drag" hint, use a disabled menu item with secondary-attributed string. You lose SwiftUI composition but gain a working menu.

Alternatively: replace `.buttonStyle(.plain)` with `MenuButtonStyle()`-equivalent custom styling that actually highlights on hover.

### 4.2 🟡 Settings list hint is misleading

`ItemsSettingsView` shows: *"⌘-drag menu bar icons to rearrange them. Items to the left of the Barred divider (|) will be hidden."*

That instruction refers to dragging items **on the real menu bar** (macOS-native behaviour), not the SwiftUI `List` below it. But the list looks eminently draggable. Users will try. Add a hint like "This list is read-only — drag items on the menu bar itself" or implement the drag (using `draggable` / `dropDestination`) so the list matches expectation.

### 4.3 🟡 `ItemsSettingsView.appsWithMultipleItems` recomputes on every render

Three O(n) passes over `detectedItems` per frame, and at 3-second scan cadence every one of them re-invalidates the list. Cache it derived from the observable state, or compute once with a single pass. Trivial to fix, surprisingly costly when the list grows to 20+ items on Dynamic-Type-large scale.

### 4.4 🟡 No empty state for untrusted + non-items-tab

Landing on the "General" tab while untrusted shows a working form. But `launchAtLogin` etc. require the app to function, which it can't without AX permission. Either surface the onboarding state globally or disable the form until trust is granted.

### 4.5 🟡 `NSPopover.behavior = .transient` + `makeKey()`

```swift
popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
popover.contentViewController?.view.window?.makeKey()
```

Calling `makeKey()` on a transient popover window is fighting with the popover's own focus semantics. Transient popovers are supposed to dismiss on any click outside; forcing key status steals focus from whatever the user was doing. Either:

- Use `.semitransient` and let the system handle focus, or
- Drop the `makeKey()` and rely on popover defaults, or
- Use a plain `NSMenu` (per §4.1).

### 4.6 🟡 `AboutView` reads `CFBundleShortVersionString` inline

```swift
Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
```

Falls back to `"?"` on failure. A missing version string in production is either a build bug (catastrophic — surface it) or impossible. Extract a `Bundle.appVersion` computed property; if it's truly missing, log it in DEBUG builds so you notice immediately. Showing "v?" to users is worse than showing nothing.

### 4.7 🟢 Low — no Reduce Motion / Dynamic Type / VoiceOver review

I didn't find any `@Environment(\.accessibilityReduceMotion)`, `@ScaledMetric`, or tested-at-large-Dynamic-Type rendering. For a menu bar app the surface area is small, but the Settings window has fixed frames and hardcoded widths that will break at large text sizes. Add at minimum a manual pass with "Larger Accessibility Sizes" enabled.

---

## 5. Testing

Tests exist and pass, which is more than most codebases at this size get. But the tests are shallow — they verify "does it crash" and "does the mock get called", not "does it behave correctly under realistic conditions".

### 5.1 🟠 Mocks don't mirror real behaviour

`MockDetector.scan()` is empty; `MockAccessibilityService.enumerateAllExtrasItems` returns `[]`. Every test runs in the degenerate case. None of the dedup, sorting, deduplication-across-screens, or findWindowID logic is exercised. A test that returns a curated list of `AXMenuBarItemInfo`s would catch entire categories of real bugs — including §1.1, §2.4, §2.5.

### 5.2 🟠 Flaky async test

`MenuBarDetectorTests.stopScanning`:

```swift
detector.startScanning()
try? await Task.sleep(for: .milliseconds(100))
detector.stopScanning()
```

That 100ms sleep is enough *usually*. Under CI load — especially the `macos-15` GitHub runners — scheduling can slip. Eventually this test will flake.

**Fix:** don't use wall-clock delays. Either expose an `onScanComplete` hook, or give the mock a counter and await a `Task.yield()` loop until it ticks.

### 5.3 🟠 `MenuBarControllerTests.start` is racy

```swift
harness.controller.start()
#expect(harness.divider.setUpCalled)
```

`start()` launches `Task { await detector.waitForFirstScan(); hideSection() }`. Because the mock returns immediately from `waitForFirstScan`, it might fire before or after the assertion depending on scheduling. Today, `setUpCalled` is set *synchronously* inside `setUp`, so *this* assertion passes — but any follow-up assertion on `divider.expandCallCount` (for the post-first-scan hideSection) would race.

**Fix:** `await Task.yield()` — better, await the controller's internal task directly via an injectable hook.

### 5.4 🟠 `AccessibilityServiceTests.checkTrust` is a tautology

```swift
#expect(service.isTrusted == false || service.isTrusted == true)
```

That is literally `#expect(true)`. The test enforces nothing. Delete it, or make it verify behaviour: construct with a fake that flips state, assert the `@Observable` notification fires.

### 5.5 🟡 No coverage for critical invariants

Missing tests that any good test plan would require:

- `MenuBarItem.isHidden` across screen layouts (the §2.5 bug).
- `MenuBarDetector.deduplicateAcrossScreens` with crafted duplicates.
- `SectionDivider.expand` + `collapse` on a stubbed NSStatusItem.
- `MenuBarController.restoreAll` after multiple toggles (current test checks only one collapse, so a regression where collapse is called twice would pass).
- `MenuBarController.scheduleAutoHide` — race between `toggleBarredBar()` and auto-hide. Today covered by `guard isBarredBarVisible else { return }` but no test verifies it.

### 5.6 🟡 `@testable import` plus `private` classes per test file

`MockDetector`, `MockAccessibilityService`, `StubAccessibilityService` are declared per-file as `private`. You have three different `AccessibilityQuerying` mocks in three files, two of which are named identically. Consolidate into a shared `Tests/BarredTests/Fakes/` folder. Keeps test files small, prevents divergence, gives you one place to upgrade mock behaviour.

---

## 6. Swift & code quality

### 6.1 🟡 `@MainActor @Observable` is the default everywhere

Every service is `@MainActor @Observable`. Fine at this size, but it means:

- Every service method runs on the main thread, which includes the AX IPC calls in §1.3.
- Anything pulling `detectedItems` off the main thread (future: background export?) will be a concurrency refactor.

Think about which services *must* be main-actor (UI views and their bindings) vs. which are incidentally main-actor (the detector, the accessibility service). Moving these to `actor` or to global-actor-agnostic classes opens the door to off-main IPC without leaking `Task { @MainActor in ... }` calls everywhere.

### 6.2 🟡 Implicitly unwrapped `NSStatusItem!` / `NSPopover!`

`AppDelegate.statusItem: NSStatusItem!` and `popover: NSPopover!`. They're only set in `applicationDidFinishLaunching` and read thereafter, so "it works". But any future code path that reads them before the delegate fires will crash with a useless message. Make them `var statusItem: NSStatusItem?` and handle the nil explicitly, or initialise in the designated init rather than the delegate callback.

### 6.3 🟡 `findWindowID` returns `0` as "not found"

```swift
private func findWindowID(for axItem: AXMenuBarItemInfo, in windows: [WindowInfo]) -> CGWindowID {
    // ...
    var bestMatch: CGWindowID = 0
    // ...
    return bestMatch
}
```

`0` is a perfectly valid CGWindowID sentinel, but you're using it as "no match found". Return `CGWindowID?` so the type system enforces the distinction. Callers can then decide explicitly what to do with no-match rather than silently grouping all unmatched items under `windowID == 0`.

### 6.4 🟡 Force-cast in `AXExtensions`

```swift
let axValue = value as! AXValue // swiftlint:disable:this force_cast
```

The guard above (`CFGetTypeID(value) == AXValueGetTypeID()`) makes this safe, but the `force_cast` SwiftLint disable is load-bearing. A safer equivalent:

```swift
guard CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
let axValue = unsafeBitCast(value, to: AXValue.self)
```

Or better yet, use `AXValueCreate`/`AXValueGetType` type-checked helpers. Not urgent; flagged because `force_cast` is a code smell that lingers and propagates.

### 6.5 🟡 Duplicated SCReenCaptureKit call path

`MenuBarDetector.detectViaAccessibility` and `detectViaWindowList` both consume the same `windows: [WindowInfo]` from `fetchStatusItemWindows`. But the ternary on lines 60–64 is hard to read:

```swift
var items: [MenuBarItem] = if accessibilityService.isTrusted {
    detectViaAccessibility(windows: windows)
} else {
    detectViaWindowList(windows: windows)
}
```

Swift 5.9 `if` expressions work but the `var` makes it harder to spot that these are two separate code paths. Extract into a single `detect(windows:)` method that branches internally, or name the variable with more intent.

### 6.6 🟡 Comments describe *what*, not *why*

CLAUDE.md already asks for minimal comments. Several existing ones violate this:

- `MenuBarItem.swift:35` — "Stable ID: prefer bundle identifier over PID (PIDs change on every app restart)" — good, this is *why*.
- `MenuBarItem.swift:40` — "Cache icon at creation time to avoid filesystem I/O on every SwiftUI render" — also *why*. Good.
- `MenuBarDetector.swift:87` — "AX-based detection enriched with window IDs" — *what*. Unnecessary.
- `MenuBarDetector.swift:205` — "Deduplication" section marker. Kill it; the method name is self-describing.

Consistency matters: either keep section headers everywhere or nowhere.

### 6.7 🟢 Redundant string interpolation

Minor: `\(Self.collapsedLength)px` inside a `Logger.debug("\()")` call — `px` is a literal, fine, but `"\(self.isBarredBarVisible)"` earlier uses `self.` explicitly only because `@Observable` sometimes needs the qualifier. Pick one style and apply consistently.

### 6.8 🟢 `@escaping () -> Void` on `SectionDivider.setUp` + custom `ActionTarget`

The `ActionTarget` class exists because you need an NSObject for `@objc` action dispatch. Fine. But the closure is captured by a private class stored on the main-actor owner — under strict concurrency, the closure needs to be `@MainActor` or `@Sendable`. Today it compiles because both sides are on the main actor, but if `SectionDivider` ever moves to a different isolation domain this breaks. Mark the closure `@MainActor @escaping () -> Void` explicitly to pin the contract.

---

## 7. Build & CI

### 7.1 🟡 `Makefile` `BUILD_DIR` computed at parse time

```makefile
BUILD_DIR = $(shell xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$NF}')
```

This is a recursively-expanded variable (`=`), so it's evaluated every time a recipe references `$(BUILD_DIR)`. But the body launches `xcodebuild -showBuildSettings` which takes 2-5 seconds. That happens for *every make target* that references `$(BUILD_DIR)`, including `make run` after `make build` — adding 5 seconds of silent wait.

**Fix:**

```makefile
BUILD_DIR := $(shell ...)
```

Single expansion at parse time. One catch: `:=` expands *on load*, even for unrelated targets like `make help`, which means `make help` takes 5 seconds to display. Use `.PHONY`-level lazy eval instead:

```makefile
build-dir:
	@xcodebuild -project $(PROJECT) -scheme $(SCHEME) -showBuildSettings 2>/dev/null | grep -m1 'BUILT_PRODUCTS_DIR' | awk '{print $$NF}'

run: build
	open "$$(xcodebuild ... | grep ... | awk ...)/Barred.app"
```

Ugly but actually correct.

### 7.2 🟡 `project.yml` deployment target mismatched with Swift 6

`SWIFT_VERSION: "6.0"` and `MACOSX_DEPLOYMENT_TARGET: "14.0"`. Swift 6 runtime libraries are bundled, so this works, but:

- Bump deployment target to 14.4 (Sonoma point release) or 15 to unlock more modern APIs — the `.tabItem` deprecation in `CODE_REVIEW.md` would be unblocked on 15+.
- Consider `SWIFT_VERSION: "6.0"` vs `"6.2"` — the latter enables better async-sequence ergonomics and actor-isolated init.

### 7.3 🟢 `project.yml` has `CODE_SIGN_IDENTITY: "-"` (ad-hoc)

Fine for dev; release signing must happen in CI. Verify that the release workflow overrides this. (I didn't audit the workflow for this review.)

---

## 8. Edge cases and failure modes not handled

An edge-case list by category. Each of these is a bug waiting to happen in the wild:

### 8.1 Screen / window manager

- Plug or unplug an external display while the bar is expanded → `expandedLength` is stale.
- Rotate a display → menu bar width changes, expansion is wrong.
- Enter/exit fullscreen → menu bar auto-hides, so `expand()` on an invisible bar is a no-op that the code thinks succeeded.
- Multiple displays with menu bars enabled ("Displays have separate Spaces") → each has its own status bar. The current code treats them as one.
- Mission Control preview → status items can be temporarily moved by macOS. Scanner may see duplicates.
- Scaled displays (Retina modes) → frame.origin.x at boundary conditions can have sub-pixel offsets that confuse `< 0` comparisons.

### 8.2 Process lifecycle

- An app is killed mid-scan → AX calls on its `AXUIElement` time out or error. Today that blocks `enumerateAllExtrasItems` until macOS returns.
- An app is mid-launch (in `runningApplications` but not yet showing a menu bar extra) → scan picks it up inconsistently, `itemIndex` churns.
- Electron apps with per-window menu bar extras → enumeration order is not even stable within a single app session.
- Apps that vend an AXExtrasMenuBar but no children → produces empty results, harmless but logged as "detected 0 items" which is noisy.

### 8.3 Permissions

- User grants AX permission *after* launch → `isTrusted` flips on next scan (good), but existing scan task is already running with `isTrusted == false`, so there's one more round of window-list fallback before the real scanner kicks in. Not a bug, just noticeable.
- User *revokes* AX permission while running → should gracefully switch to fallback mode. Today `checkTrust()` is re-polled per scan, so it *does* switch — but there's no user-facing notification.
- Screen Recording permission (required by ScreenCaptureKit on some macOS versions) is never requested. If the user has it denied, `fetchStatusItemWindows` fails silently (just logs an error and returns `[]`). Prompt for it.

### 8.4 Preferences / data

- Corrupted `UserDefaults` blob → silent reset (§3.1).
- Two Macs syncing via iCloud Keychain or Handoff: `UserDefaults.standard` is not synced, so preferences don't follow, but if you ever add that feature, schema migrations need to be in place.
- Preference decoding failure on a field that's *not* `autoHideDelay` (there are three total) would currently fall through to the default struct — quiet data loss. Tests only cover the one field.

### 8.5 Auto-hide

- User opens the Barred bar, auto-hide fires at 5s, user is mid-interaction with a now-hidden menu item → the click falls through to whatever is behind.
- System sleep during the auto-hide timer → `Task.sleep` continues counting wall time, so on wake the bar immediately collapses. Probably desired, but document it.
- User changes `autoHideDelay` *while* a timer is running → the in-flight timer uses the old value. Today: acceptable. If a user complains, reschedule on change.

### 8.6 Threads / concurrency

- `applicationWillTerminate` calls `controller.restoreAll()`. If a scan is in flight, `stopScanning()` cancels the task but the `scan()` coroutine itself is still running on the main actor during termination. macOS gives you ~100ms. If SCShareableContent is mid-IPC, you block termination.
- `checkTrust()` is called from `statusItemClicked` synchronously then `requestTrust()` (which shows a system prompt) then `toggleBarredBar()`. The prompt is modal — it steals focus. The toggle runs anyway. Race: user clicks "Allow" after the toggle has already fired. State is wrong.

---

## 9. Process recommendations for the team

Less about code, more about how to not accumulate these issues:

1. **A PR checklist.** For anything touching the scanning path: "does this run on the main thread? does it make IPC calls? is there a timeout?" Forces the conversation to happen at review time, not post-ship.
2. **A "failure mode" section in PR descriptions.** "What happens if this fails?" Three bullets is enough. Catches §1.1 and §1.4 before they ship.
3. **Stop using `try?` as a default.** Every `try?` is a decision to swallow errors. Log, rethrow, or handle — pick one. "Silently return nil" is never the right answer outside of genuinely-optional lookups.
4. **Test realistic scenarios, not just the happy path.** Every bug in §8 would be caught by a test that runs with crafted fake inputs. Your mocks today return empty arrays; replace them with scenario fakes.
5. **Delete code aggressively.** `axElement` on `MenuBarItem`, the `// MARK: -` section headers, the `CODE_REVIEW.md` "previously resolved" section once items have bedded in. A smaller codebase is a safer codebase.
6. **Budget for a "battery impact" review before each release.** For a menu bar app, this is the top user complaint category. Profile with Instruments → Energy and compare against baseline Activity Monitor idle energy.

---

## 10. What this codebase does well

To stay honest — a few things are better than typical:

- **Clear module boundaries.** Services / Models / Views / Utilities is consistent and navigable.
- **`@Observable` + `@Environment` is used correctly.** No manual `@ObservableObject` + `@Published` boilerplate, no accidental re-renders from bad bindings.
- **Strict concurrency on.** `SWIFT_STRICT_CONCURRENCY: complete` is aspirational for most codebases; here it's enforced. That compile-time pressure has kept `Sendable` issues at bay so far.
- **SwiftLint + SwiftFormat + pre-commit hooks** are set up. Many projects skip these until year two.
- **Existing `CODE_REVIEW.md`** — self-audits are a healthy habit. Keep doing them, and be ruthless about pruning the "resolved" section once items have stuck.
- **Tests exist.** Imperfect, but non-zero, and the structure is there to build on.

---

## Prioritised punch list

If I had two weeks, in order:

**Week 1 — correctness**

1. Fix `waitForFirstScan` and re-entrancy in `scan()` (§1.1, §1.2).
2. Add `AXUIElementSetMessagingTimeout` to every AX call path + move off-main (§1.3).
3. Fix launch-at-login toggle loop (§1.4).
4. Fix `MenuBarItem.isHidden` multi-monitor bug (§2.5).
5. Inject `UserDefaults` into `PreferencesStore` and stop polluting global state in tests (§3.2).

**Week 2 — architecture & polish**

6. Move `detector.startScanning()` out of init (§2.1).
7. Replace 3s polling with notification-driven scanning (§1.5).
8. Replace `BarredMenuView` VStack with a real menu (§4.1).
9. Scenario-based mocks in tests; delete tautology assertions (§5.1, §5.4).
10. Handle screen-change and sleep/wake notifications in `SectionDivider` (§2.6).

Everything else is nice-to-have.

---

## Final words for the junior engineers on the team

You didn't write most of this in a vacuum, and fixing it isn't about assigning blame — a codebase reflects the constraints it was built under. Reading this review you should take away three things:

1. **Concurrency primitives have precise contracts.** `CheckedContinuation`, `Task`, `@MainActor`, `Sendable` — learn the contracts, don't pattern-match from StackOverflow. Every concurrency bug in this review stems from using a primitive outside its guarantees.
2. **Assume every external call fails.** IPC. File I/O. `SMAppService`. Notifications. Every single one. The code that handles the failure is 80% of the real work; the happy path is the easy part.
3. **Make invariants explicit.** If a comment says "must be called after X", an assert, a type, or an API design should enforce that — not a comment. Comments rot; types don't.

The codebase is recoverable. None of this is a rewrite. Work through the punch list, and the next review will be a much shorter document.
