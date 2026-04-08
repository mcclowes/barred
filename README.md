# Barman

A macOS menu bar manager. Detects and organises menu bar items from other apps — hide, reorder, or tuck them into a secondary bar.

Built with Swift 6 and SwiftUI. Requires macOS 14 (Sonoma) or later.

## How it works

Barman sits in your menu bar and uses macOS Accessibility APIs to detect items from other apps. You can choose which items to always show, hide, or move into a collapsible "Barman bar". Hidden items are moved off-screen using private CoreGraphics APIs (same approach as Bartender).

## Build

Requires Xcode 16+ (Swift 6 toolchain).

```bash
swift build                # debug build
./Scripts/build-app.sh     # build .app bundle to .build/Barman.app
open .build/Barman.app     # run it
```

## Setup

On first launch, grant Accessibility access when prompted:

**System Settings > Privacy & Security > Accessibility > Barman**

Without this, Barman can't detect or manage other apps' menu bar items.

## License

TBD
