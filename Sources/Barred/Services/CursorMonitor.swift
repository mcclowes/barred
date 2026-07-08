import AppKit
import Foundation

/// Extra vertical slack when matching a popup's top edge to the menu bar,
/// covering the small gap system panels (e.g. Control Center) leave below it.
/// File-scoped so the pure `nonisolated` geometry helpers can read it without
/// crossing the `@MainActor` isolation of `CursorMonitor`.
private let menuBarAnchorSlop: CGFloat = 12

@MainActor
protocol CursorMonitoring {
    /// True when the cursor is anywhere within the menu-bar strip (the top
    /// `NSStatusBar.thickness` band of any connected screen). Keeps the
    /// revealed section open while the user is working along the menu bar.
    func isInMenuBarStrip() -> Bool

    /// True when the cursor is over an open menu-bar dropdown/popover — e.g. a
    /// third-party item's menu, or a system panel like WiFi/Control Center that
    /// opens below the bar. Keeps the section open while the user interacts with
    /// that menu even though the cursor has left the strip itself.
    func isOverMenuBarPopup() -> Bool
}

@MainActor
struct CursorMonitor: CursorMonitoring {
    func isInMenuBarStrip() -> Bool {
        Self.isInMenuBarStrip(
            mouse: NSEvent.mouseLocation,
            screens: NSScreen.screens.map(\.frame),
            menuBarThickness: NSStatusBar.system.thickness
        )
    }

    func isOverMenuBarPopup() -> Bool {
        Self.isOverMenuBarPopup(
            mouse: NSEvent.mouseLocation,
            screens: NSScreen.screens.map(\.frame),
            primaryHeight: Self.primaryHeight,
            menuBarThickness: NSStatusBar.system.thickness,
            windows: Self.onScreenWindows()
        )
    }

    // MARK: - System snapshots

    /// Height of the primary display (the one at the global origin). CoreGraphics
    /// window bounds use a top-left origin anchored to this display, so we need
    /// its height to convert between Cocoa and CG coordinates.
    private static var primaryHeight: CGFloat {
        let screens = NSScreen.screens
        let primary = screens.first(where: { $0.frame.origin == .zero }) ?? screens.first
        return primary?.frame.height ?? 0
    }

    /// Lightweight probe of on-screen windows. Reads only layer + bounds, so it
    /// needs no Screen Recording permission (that gate only covers window names
    /// and captured pixels, not geometry).
    private static func onScreenWindows() -> [WindowSnapshot] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return info.compactMap { dict in
            guard let layer = dict[kCGWindowLayer as String] as? Int,
                  let boundsDict = dict[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            return WindowSnapshot(layer: layer, bounds: bounds)
        }
    }

    // MARK: - Pure geometry (testable, no system dependencies)

    /// A window's layer and CoreGraphics bounds (top-left origin, y grows down).
    struct WindowSnapshot: Equatable {
        let layer: Int
        let bounds: CGRect
    }

    nonisolated static func isInMenuBarStrip(
        mouse: CGPoint,
        screens: [CGRect],
        menuBarThickness: CGFloat
    ) -> Bool {
        screens.contains { screen in
            mouse.y >= screen.maxY - menuBarThickness
                && mouse.y <= screen.maxY
                && mouse.x >= screen.minX
                && mouse.x <= screen.maxX
        }
    }

    /// The cursor counts as "over a menu-bar popup" when it sits inside an
    /// above-normal window (`layer > 0`, i.e. a menu/panel rather than a regular
    /// app window at layer 0 or the desktop below it) whose top edge is anchored
    /// to the menu bar of some screen — the shape a dropdown descending from the
    /// bar always has.
    nonisolated static func isOverMenuBarPopup(
        mouse: CGPoint,
        screens: [CGRect],
        primaryHeight: CGFloat,
        menuBarThickness: CGFloat,
        windows: [WindowSnapshot]
    ) -> Bool {
        let mouseCG = CGPoint(x: mouse.x, y: primaryHeight - mouse.y)
        // Menu bar top edge of each screen, in CG (top-left) coordinates.
        let screenTopsCG = screens.map { screen -> CGRect in
            CGRect(
                x: screen.minX,
                y: primaryHeight - screen.maxY,
                width: screen.width,
                height: screen.height
            )
        }
        return windows.contains { window in
            guard window.layer > 0, window.bounds.contains(mouseCG) else { return false }
            return screenTopsCG.contains { screen in
                window.bounds.maxX > screen.minX
                    && window.bounds.minX < screen.maxX
                    && window.bounds.minY >= screen.minY - menuBarAnchorSlop
                    && window.bounds.minY <= screen.minY + menuBarThickness + menuBarAnchorSlop
            }
        }
    }
}
