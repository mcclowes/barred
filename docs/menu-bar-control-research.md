# Menu bar item control research

Research into how macOS menu bar manager apps (Bartender, Ice, Dozer, Hidden Bar) control third-party menu bar items.

## Three approaches

### 1. Expanded NSStatusItem length (Dozer, Hidden Bar)

The simplest and most reliable technique. No private APIs, no Accessibility permission needed.

- Create your own `NSStatusItem` dividers as section markers
- To "hide" items to the left of a divider, set the divider's `length` to ~10,000 points
- This pushes everything left of it off-screen (menu bar lays out right-to-left)
- Users Cmd+drag their icons to arrange sections

```swift
// Hide everything left of divider
dividerItem.length = 10_000

// Show everything
dividerItem.length = 20
```

**Pros:** No private APIs, no Accessibility permission, App Store safe, extremely reliable.

**Cons:** All-or-nothing per section — can't selectively hide individual items without user rearrangement via Cmd+drag.

**References:**
- [Dozer](https://github.com/Mortennn/Dozer) — `StatusIconClasses/HelperStatusIcon.swift`
- [Hidden Bar](https://github.com/dwarvesf/hidden) — `StatusBarController.swift`

### 2. Synthetic CGEvent Cmd+drag (Ice)

Ice simulates the native Cmd+drag gesture to programmatically reorder items between sections.

- Synthesize `CGEvent` mouse events with `.maskCommand` modifier
- Target specific window IDs via private `CGEventField` values
- Move items between visible/hidden sections, then use approach #1 to hide the section
- Retries up to 5 times if the frame doesn't change

This enables per-item control without user interaction but requires private CGS APIs.

**Private APIs used by Ice:**
- `CGSMainConnectionID()` — get connection to WindowServer
- `CGSGetWindowList` / `CGSGetOnScreenWindowList` — enumerate windows
- `CGSGetProcessMenuBarWindowList` — get menu bar windows specifically
- `CGSGetScreenRectForWindow` — get precise window frames

**Pros:** Per-item granularity, no user interaction needed for rearrangement.

**Cons:** Private APIs (no App Store), can break across macOS updates, complex implementation.

**Reference:** [Ice](https://github.com/jordanbaird/Ice) — `MenuBarItemManager.swift`, `Bridging/Shims/Private.swift`

### 3. AXUIElement position manipulation (Barred's current approach)

Setting `kAXPositionAttribute` to move items off-screen (x: -10000).

```swift
AXUIElementSetAttributeValue(element, kAXPositionAttribute, value)
```

**This approach is unreliable on modern macOS.** The position attribute is typically not settable for status item windows. System items (Control Centre, Spotlight, Clock) and many third-party `NSStatusItem` windows reject AX position changes.

**Not recommended.**

## Menu bar item categories

### System "Control Centre" items
Owned by `com.apple.controlcenter`: Wi-Fi, Bluetooth, Battery, Sound, Focus, Screen Mirroring, Clock, Spotlight, Siri. Run inside ControlCenter.app.

### SystemUIServer items
Legacy "menu extras" like Time Machine, VPN indicators. Run inside SystemUIServer using the private `NSMenuExtra` class.

### Third-party NSStatusItem items
Created via `NSStatusBar.system.statusItem(withLength:)`. Each runs in its own app process. Primary target for menu bar managers.

## Immovable items

These cannot be moved even with Cmd+drag:
- Clock (`com.apple.controlcenter:Clock`)
- Siri (`com.apple.systemuiserver:Siri`)
- Control Centre BentoBox (`com.apple.controlcenter:BentoBox`)

## Technical details

- All status items appear as windows on layer 25 (`kCGStatusWindowLevel`)
- Each status item has its own window with a unique `CGWindowID`
- Position preferences stored in UserDefaults as `NSStatusItem Preferred Position <autosaveName>`
- Menu bar height is fixed at 24pt for status item content
- Item spacing controlled by `NSStatusItemSpacing` (default: 16) and `NSStatusItemSelectionPadding` (default: 16)

## macOS version considerations

### Sonoma (macOS 14)
Stable baseline. Ice targets macOS 14+ as minimum.

### Sequoia (macOS 15)
Internal changes to menu bar rendering caused Bartender compatibility issues (Apple menu randomly opening). Bartender 6 had to rebuild its "Bartender Bar."

### Tahoe (macOS 26)

Major breaking changes:

**CGWindowListCopyWindowInfo regression ([FB18327911](https://github.com/feedback-assistant/reports/issues/679)):**
- All status items reported as owned by Control Centre (`kCGWindowOwnerPID` returns Control Centre's PID), regardless of actual owner
- Filed June 2025, remains open with no Apple response
- `CGSGetProcessMenuBarWindowList` (private) still works for enumerating window IDs but has the same ownership misattribution

**AXExtrasMenuBar regression:**
- Querying `kAXExtrasMenuBarAttribute` on Control Centre only returns its own items
- Querying on **individual app PIDs still works correctly** — this is the basis of the workaround (see below)

**Built-in menu bar management:**
- System Settings > Menu Bar now has per-app "Allow in the Menu Bar" toggles
- Settings stored in `~/Library/GroupContainers/group.com.apple.controlcenter/Library/Preferences/group.com.apple.controlcenter.plist`
- **No public API** to read/write these settings ([FB7087526](https://github.com/feedback-assistant/reports/issues/37), open since 2019)
- `NSStatusItem.isVisible` reflects the app's intent, not whether the system has hidden it
- Apple suggests monitoring `NSWindowDidChangeOcclusionStateNotification` as a workaround

**Other changes:**
- Liquid Glass design — transparent menu bar aesthetic
- iPhone Live Activities now appear in the menu bar
- Item movement via Accessibility APIs became sluggish
- No new public menu bar management APIs announced at WWDC 2025
- WWDC 2025 menu bar focus was on bringing `MenuBarExtra` to iPadOS, not new macOS APIs

### Tahoe workaround: spatial matching (used by Thaw/Ice)

The recommended approach for identifying item ownership on macOS 26:

1. Enumerate menu bar windows via `CGSGetProcessMenuBarWindowList` (private, for window IDs and positions)
2. For each running app, query its `AXExtrasMenuBar` children (public Accessibility API)
3. **Match window IDs to source PIDs by comparing frame center coordinates** (1pt distance threshold)
4. Run matching in background thread or XPC service (AX calls can block on unresponsive apps)
5. Cache results keyed by `CGWindowID`, clean up periodically

Implementation reference: [Thaw's `SourcePIDCache.swift`](https://github.com/stonerl/Thaw)

```swift
// Core matching logic from Thaw
if let matchedWindow = allWindows.first(where: {
    $0.bounds.center.distance(to: childCenter) <= 1
}) {
    state.withLock { $0.pids[matchedWindow.windowID] = pid }
}
```

### Expanded-length technique on Tahoe

The `NSStatusItem.length` expansion technique **still works on Tahoe**, with caveats:

- **Use bounded values** (e.g., `max(500, min(screenWidth + 200, 4000))`) — values of 10,000 cause multi-GB memory leaks due to expensive layout/repaint in newer macOS menu bar internals (Hidden Bar [#344](https://github.com/dwarvesf/hidden/pull/344))
- **Live Activities conflict** — iPhone Live Activities in the menu bar get incorrectly pushed offscreen
- **Ultrawide monitors** — the expanded item can "split" on very wide displays (5117px+), showing hidden items on the far edges

`NSStatusItem.length` is **not deprecated** in Apple's documentation.

### How other apps adapted to Tahoe

| App | Status | Approach |
|-----|--------|----------|
| **[Thaw](https://github.com/stonerl/Thaw)** (Ice fork) | Active (v1.2.0-rc.4, March 2026) | Spatial matching via XPC service, AXSwift, 3s timeout for unresponsive apps |
| **Bartender 6** | Working (March 2026 rewrite) | Full rewrite, added "Layout Mode" (On-Demand vs Live) to work around cursor/click hijacking |
| **Hidden Bar** | Working | Bounded length values, but Live Activities and ultrawide issues |
| **Ice** | Stalled | 50+ open Tahoe issues, development appears inactive |
| **Dozer** | Unmaintained | Crashes on Tahoe (EXC_BAD_INSTRUCTION), runs under Rosetta |

## Future-proofing strategy for Barred

### API safety tiers

**Safe (public, stable):**
- `MenuBarExtra` (SwiftUI) / `NSStatusItem` (AppKit) — for your own items
- `NSStatusItem.length` — for the expanded-length hiding technique
- `NSWorkspace.shared.runningApplications` — app discovery
- AXUIElement per-app `AXExtrasMenuBar` queries — item enumeration (requires Accessibility permission)
- `NSWindowDidChangeOcclusionStateNotification` — detect if your own item is visible

**At risk (private or broken):**
- `CGWindowListCopyWindowInfo` `kCGWindowOwnerPID` — broken for menu bar items on Tahoe
- `CGSGetProcessMenuBarWindowList` — private, works now but could break
- Any reliance on `kCGWindowOwnerPID` for menu bar items

### Recommended architecture

1. **Primary hiding mechanism:** Expanded-length `NSStatusItem` dividers (bounded to `screenWidth + 200`, max 4000)
2. **Item detection:** AX-based per-app `AXExtrasMenuBar` enumeration (public API, still works on Tahoe)
3. **Window ID matching:** Spatial matching (frame center comparison) rather than PID-based matching
4. **Background processing:** Run AX enumeration in background thread with timeouts for unresponsive apps
5. **Graceful degradation:** If AX detection fails, fall back to pure divider-based hiding (like Hidden Bar)
6. **Monitor Apple changes:** Watch for public menu bar management APIs in future macOS releases

### What to avoid

- Don't rely on `CGWindowListCopyWindowInfo` for ownership — broken on Tahoe
- Don't use AX position manipulation for hiding — unreliable on all modern macOS
- Don't use excessively large `NSStatusItem.length` values — causes memory leaks
- Don't assume all items can be moved — Clock, Siri, BentoBox are immovable

## References

- [Ice](https://github.com/jordanbaird/Ice) — most sophisticated open-source menu bar manager
- [Thaw](https://github.com/stonerl/Thaw) — actively maintained Ice fork with Tahoe fixes
- [Dozer](https://github.com/Mortennn/Dozer) — simple expanded-length approach
- [Hidden Bar](https://github.com/dwarvesf/hidden) — similar to Dozer, bounded length fix
- [CGSInternal (NUIKit)](https://github.com/NUIKit/CGSInternal) — CGS private API documentation
- [Multi blog: Pushing the limits of NSStatusItem](https://multi.app/blog/pushing-the-limits-nsstatusitem)
- [MacPaw: Parsing macOS app UI](https://research.macpaw.com/publications/how-to-parse-macos-app-ui)
- [FB18327911: CGWindowListCopyWindowInfo regression](https://github.com/feedback-assistant/reports/issues/679)
- [FB7087526: Detect if NSStatusBarItem is force hidden](https://github.com/feedback-assistant/reports/issues/37)
- [Bartender back on Tahoe (March 2026)](https://9to5mac.com/2026/03/11/bartender-for-mac-is-good-again-and-my-menu-bar-is-very-thankful/)
