# Product requirements

## Overview

Barred is a lightweight macOS menu bar manager. It lets users hide, reorder, and organise menu bar icons by tucking rarely-used items into a collapsible secondary section.

## Target user

Mac users with cluttered menu bars who want a simple, free, native tool — not a full-featured paid app like Bartender.

## Platform

- macOS 14 (Sonoma) or later
- Runs as an accessory app (no dock icon)
- Requires Accessibility permission

## Core features

### Hide menu bar items
Users can hide individual menu bar icons from other apps. Hidden items are pushed off-screen by expanding an invisible divider — the same technique used by Dozer and Hidden Bar.

### Collapsible secondary bar
Hidden items aren't gone — they're accessible with a single click on the Barred icon or the section divider. The secondary bar slides into view, then auto-hides after a configurable delay.

### Reorder items
Users can Cmd-drag menu bar icons to rearrange their order (native macOS behaviour that Barred preserves).

### Auto-hide
The secondary bar automatically collapses after a user-configurable delay (1–15 seconds).

### Launch at login
Optional setting to start Barred automatically on login via the Login Items API.

## Non-functional requirements

- **Lightweight**: minimal CPU and memory footprint; no background processing beyond a 3-second scan interval.
- **No dock icon**: runs as an LSUIElement/accessory app.
- **Privacy**: no network access, no analytics, no data collection.
- **Accessibility**: relies on the macOS Accessibility API (AXUIElement) with a CGWindowList fallback for when trust hasn't been granted yet.

## Distribution

- Homebrew cask (`brew tap mcclowes/barred && brew install --cask barred`)
- GitHub Releases (notarized .app in a zip)

## Out of scope (for now)

- Per-app hide rules (auto-hide specific apps' icons)
- Icon grouping / folders
- Menu bar theming or custom icons
- iOS / iPadOS
