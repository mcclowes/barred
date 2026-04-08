# Barred

A macOS menu bar manager. Detects and organises menu bar items from other apps — hide, reorder, or tuck them into a secondary bar.

Built with Swift 6 and SwiftUI. Requires macOS 14 (Sonoma) or later.

## How it works

Barred sits in your menu bar and uses macOS Accessibility APIs to detect items from other apps. You can choose which items to always show, hide, or move into a collapsible "Barred bar". Hidden items are pushed off-screen by expanding a divider status item (same approach as Dozer and Hidden Bar).

## Build

Requires Xcode 16+ (Swift 6 toolchain) and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```bash
make build                 # debug build
make app                   # build .app bundle
make run                   # build and run
make test                  # run tests
```

## Setup

On first launch, grant Accessibility access when prompted:

**System Settings > Privacy & Security > Accessibility > Barred**

Without this, Barred can't detect or manage other apps' menu bar items.

## License

TBD
