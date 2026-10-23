# Barred

[![Release](https://github.com/mcclowes/barred/actions/workflows/release.yml/badge.svg)](https://github.com/mcclowes/barred/actions/workflows/release.yml)

A lightweight macOS menu bar manager. Hide, reorder, and organise your menu bar icons — tuck the ones you don't need into a collapsible secondary bar.

## Install

**Homebrew (recommended):**

```bash
brew tap mcclowes/barred
brew install --cask barred
```

**Manual:**

Download `Barred.zip` from the [latest release](https://github.com/mcclowes/barred/releases/latest), extract it, and move `Barred.app` to your Applications folder.

## Getting started

Barred needs Accessibility permission to detect and manage menu bar items from other apps. Option-click its menu bar icon and choose **Grant accessibility access...** to request it, then enable Barred in:

**System Settings → Privacy & Security → Accessibility → Barred**

By default, click the Barred icon to toggle the hidden section. **Alt-click (Option-click)** it to open the menu, including **Settings...** and **Quit Barred**.

In **Settings → General**, **Show Barred bar on click** controls normal clicks. Option-click always opens the menu:

| Show Barred bar on click | Click | Option-click |
| --- | --- | --- |
| On (default) | Toggle the hidden section | Open the menu |
| Off | Open the menu | Open the menu |

On macOS 27, run Barred from **Applications**, then click it to reveal two vertical lines. **⌘-drag icons between the lines** to include them in the hidden section. Icons outside either line stay visible. Clicking Barred hides or reveals that section. macOS hides all icons belonging to an app together; if that app also has an icon outside the section, it stays visible. System controls always stay visible.

On macOS 26 and earlier, there is one divider: ⌘-drag icons to its left to hide them.

Click a divider while it is visible to toggle the section. After revealing the section, Barred hides it again after five seconds of inactivity by default. The idle timer resets while you drag an item, keep the pointer in the menu bar, or hover over a menu bar dropdown. Change **Auto-hide delay** in **Settings → General** from 1 to 15 seconds.

## Features

- **Hide menu bar items** — declutter your menu bar by hiding icons you rarely need
- **Collapsible secondary bar** — hidden items are tucked away but accessible with a single click
- **Reorder items** — ⌘-drag menu bar icons to rearrange them
- **Auto-hide** — the secondary bar hides itself after a configurable delay (1–15 seconds)
- **Launch at login** — start Barred automatically when you log in
- **Lightweight** — no dock icon, minimal resource usage

## Requirements

- macOS 14 (Sonoma) or later

## How it works

Barred uses macOS Accessibility APIs to detect status items from running apps. On macOS 26 and earlier, it pushes hidden items off-screen by expanding a divider. macOS 27 changed menu bar layout, so Barred instead hides the apps between two section markers through the private `MenuBarClientCore` framework. That API is checked at runtime; if it is unavailable or hiding fails, the section stays visible. Showing the section or quitting releases the visibility restriction.

## Building from source

Requires Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
make build                 # debug build
make app                   # build .app bundle
make run                   # build and run with Apple Development signing
make test                  # run tests
```

`make run` requires an Apple Development signing identity in your keychain. This gives local builds a stable identity so Accessibility permission survives rebuilds. It defaults to the Codogo team; use `DEV_DEVELOPMENT_TEAM=YOUR_TEAM_ID` and `DEV_CODE_SIGN_IDENTITY="Your signing identity"` to override the team and certificate.

Development and installed release builds need separate initial Accessibility approval. If Barred is already enabled but the development build still requests access, quit Barred, remove its stale entry from **System Settings → Privacy & Security → Accessibility**, then launch `make run` and approve that build once. `make build` and `make test` still use ad-hoc signing and don't require a certificate.

For live hiding tests on macOS 27, install the signed development app in Applications and launch that copy. macOS resolves visibility rules through the registered application; Barred leaves everything visible if a different copy is registered, rather than risking hiding its own controls. `make run` builds and launches the development output but doesn't replace an installed app.

To check the native layout race, quit Barred and run `open /Applications/Barred.app --args --verify-menu-bar-layout` with a Debug build and at least one app between the markers. This runs twelve show/hide cycles with immediate, 50 ms, 100 ms, and 150 ms toggles, then quits and restores the icons. `/private/tmp/barred-layout-check.json` reports `completedCycles: 12` and `passed: true` only when every cycle successfully selects the same nonempty group. This checks selection stability; rendered visibility still needs a visual check. Relaunch Barred normally afterward.

See the [Makefile](Makefile) for all available targets.

## License

TBD
