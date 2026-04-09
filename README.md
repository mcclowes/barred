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

Once granted, Barred appears in your menu bar. Click it to toggle the hidden items bar, or open the settings to configure which items are visible.

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
make run                   # build and run
make test                  # run tests
```

See the [Makefile](Makefile) for all available targets.

## License

TBD
