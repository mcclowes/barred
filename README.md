# Barred

[![Release](https://github.com/mcclowes/barred/actions/workflows/release.yml/badge.svg)](https://github.com/mcclowes/barred/actions/workflows/release.yml)

A lightweight macOS menu bar manager. Hide, reorder, and organise your menu bar icons — tuck the ones you don't need into a collapsible secondary bar.

## Related repos and prerequisites

**This repo:** Native macOS menu bar manager.

**Account prerequisite:** No Marginal Utility account is required for local use.

| Related repository | Relationship |
| --- | --- |
| [homebrew-barred](https://github.com/mcclowes/homebrew-barred) | Homebrew distribution; app/CLI source lives here. |
| [marginal-utility](https://github.com/mcclowes/marginal-utility) | Hosts the product marketing page and documentation. |

See the [project reference](https://github.com/mcclowes/marginal-utility/blob/main/ECOSYSTEM.md) for the full repository map. Some source repositories require access; public product homes and Homebrew taps remain the entry points for downloads and support.

## Install

**Homebrew (recommended):**

```bash
brew install --cask mcclowes/barred/barred
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
- Apple silicon Mac for the current release download (v1.1.4)

## How it works

Barred uses macOS Accessibility APIs to detect status items from running apps. On macOS 26 and earlier, it pushes hidden items off-screen by expanding a divider. macOS 27 changed menu bar layout, so Barred instead hides the apps between two section markers through the private `MenuBarClientCore` framework. That API is checked at runtime; if it is unavailable or hiding fails, the section stays visible. Showing the section or quitting releases the visibility restriction.

## Building from source

Requires Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
make build                 # debug build
make app                   # build .app bundle
make run                   # build and run with Apple Development signing
make test                  # run tests
make test-build-helper     # check packaging with stubbed build/signing tools
make test-bump-helper      # check version arguments and metadata in disposable repositories
make test-run              # check Make arguments and launch paths with stubs
make test-release-paths    # check release path lookups with fake Xcode
```

`make run` requires an Apple Development signing identity in your keychain. This gives local builds a stable identity so Accessibility permission survives rebuilds. It defaults to the Codogo team; use `DEV_DEVELOPMENT_TEAM=YOUR_TEAM_ID` and `DEV_CODE_SIGN_IDENTITY="Your signing identity"` to override the team and certificate.

Development and installed release builds need separate initial Accessibility approval. If Barred is already enabled but the development build still requests access, quit Barred, remove its stale entry from **System Settings → Privacy & Security → Accessibility**, then launch `make run` and approve that build once. `make build` and `make test` still use ad-hoc signing and don't require a certificate.

For live hiding tests on macOS 27, install the signed development app in Applications and launch that copy. macOS resolves visibility rules through the registered application; Barred leaves everything visible if a different copy is registered, rather than risking hiding its own controls. `make run` builds and launches the development output but doesn't replace an installed app.

To check the native layout race, quit Barred and run `open /Applications/Barred.app --args --verify-menu-bar-layout` with a Debug build and at least one app between the markers. This runs twelve show/hide cycles with immediate, 50 ms, 100 ms, and 150 ms toggles, then quits and restores the icons. `/private/tmp/barred-layout-check.json` reports `completedCycles: 12` and `passed: true` only when every cycle successfully selects the same nonempty group. This checks selection stability; rendered visibility still needs a visual check. Relaunch Barred normally afterward.

See the [Makefile](Makefile) for all available targets.

`make run` uses Debug build settings, preserves paths containing spaces, and stops
on build or settings lookup failures. `make test-run` checks those behaviors plus
default/custom project and scheme arguments and Xcode failures for build, release,
test, and clean. Fixtures use stubbed Xcode/open commands and disposable outputs;
failed Xcode cleanup preserves the prior app and archive. Native tests retain the
dedicated `BarredTests` scheme.

The [command catalog](.clip/commands.md) describes each target's effects,
including hosted tests that launch the app and packaging that can notarize it.

`make install-hooks` replaces the pre-commit hook at Git's active destination,
including a configured `core.hooksPath`. It stages the replacement beside the
destination, leaving the previous hook intact if copying, permissions, or promotion
fails. Linked worktrees normally share the default hook. `make test-install-hooks`
checks installation and failures in disposable repositories without changing your
installed hook.

`make app` preserves Xcode's built version, build number, and resolved app metadata. Set `VERSION` or `BUILD_NUMBER` to override only that value for packaging.

The helper prepares and signs the app in temporary staging, validates the ZIP,
and computes its checksum before replacing the normal outputs. Preparation
failures keep the previous app and ZIP intact and remove staging. Before
publication, the helper backs up existing outputs in staging. Failed moves or
handled HUP, INT, or TERM signals restore them; a failed restore retains staging
and reports its recovery path. App and ZIP publication uses separate moves, so
this recovery does not make the pair atomic against a crash or forced termination.

Maintainers: see the [Homebrew release guide](docs/homebrew-release.md) for signing credentials, version bumps, and publishing.

## License

TBD
