import AppKit
import Foundation

@MainActor
protocol CursorMonitoring {
    /// True when the cursor is over the menu-bar y-strip and within the
    /// horizontal extent of any visible item (with a small slop for the
    /// section divider and the cursor's own width).
    func isOverMenuBarItems(_ items: [MenuBarItem]) -> Bool
}

@MainActor
struct CursorMonitor: CursorMonitoring {
    /// Extra horizontal padding around the item bounding box. Covers the
    /// section divider on either side and avoids flicker right at the edge.
    private static let horizontalPadding: CGFloat = 16

    func isOverMenuBarItems(_ items: [MenuBarItem]) -> Bool {
        let visible = items.filter { !$0.isHidden }
        guard !visible.isEmpty else { return false }

        let mouse = NSEvent.mouseLocation
        let menuBarThickness = NSStatusBar.system.thickness

        let inMenuBarStrip = NSScreen.screens.contains { screen in
            mouse.y >= screen.frame.maxY - menuBarThickness
                && mouse.y <= screen.frame.maxY
                && mouse.x >= screen.frame.minX
                && mouse.x <= screen.frame.maxX
        }
        guard inMenuBarStrip else { return false }

        let padding = Self.horizontalPadding
        return visible.contains { item in
            mouse.x >= item.frame.minX - padding && mouse.x <= item.frame.maxX + padding
        }
    }
}
