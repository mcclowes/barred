# Barred

[![Release](https://github.com/mcclowes/barred/actions/workflows/release.yml/badge.svg)](https://github.com/mcclowes/barred/actions/workflows/release.yml)

A lightweight macOS menu bar manager. Hide, reorder, and organise your menu bar icons — tuck the ones you don't need into a collapsible secondary bar.

## Install

**Homebrew (recommended):**

```bash
brew install --cask mcclowes/barred/barred
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
- Apple silicon Mac for the current release download (v1.1.4)

## How it works

Barred uses macOS Accessibility APIs to detect status items from running apps. A divider separates visible items from hidden ones — hidden items are pushed off-screen by expanding the divider. This is the same approach used by [Dozer](https://github.com/Mortennn/Dozer) and [Hidden Bar](https://github.com/dwarvesf/hidden).

## Building from source

Requires Xcode 16+ and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
make build                 # debug build
make app                   # build .app bundle
make run                   # build and run
make test                  # run tests
make test-build-helper     # check packaging with stubbed build/signing tools
make test-bump-helper      # check version bumps with stubbed Git
make test-run              # check launch paths with stubbed build/launch tools
```

See the [Makefile](Makefile) for all available targets.

`make run` uses Debug build settings, preserves paths containing spaces, and stops
on build or settings lookup failures. `make test-run` checks these behaviors
without building or launching Barred.

The [command catalog](.clip/commands.md) describes each target's effects,
including hosted tests that launch the app and packaging that can notarize it.

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
