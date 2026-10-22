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

On first launch, Barred will ask for Accessibility permission. This is required to detect and manage menu bar items from other apps.

**System Settings → Privacy & Security → Accessibility → Barred**

Once granted, Barred appears in your menu bar. Click it to toggle the hidden items bar. **Alt-click (Option-click)** the Barred icon to open its menu, including **Settings...** and **Quit Barred**.

In Settings, turning off **Show Barred bar on click** makes normal clicks open the menu too. Option-click always opens the menu.

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

Barred uses macOS Accessibility APIs to detect status items from running apps. A divider separates visible items from hidden ones — hidden items are pushed off-screen by expanding the divider. This is the same approach used by [Dozer](https://github.com/Mortennn/Dozer) and [Hidden Bar](https://github.com/dwarvesf/hidden).

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

See the [Makefile](Makefile) for all available targets.

## License

TBD
