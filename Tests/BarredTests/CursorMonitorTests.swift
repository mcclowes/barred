@testable import Barred
import Foundation
import Testing

struct CursorMonitorTests {
    // A 2560×1440 primary display at the global origin, menu bar 24pt tall.
    private let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
    private let primaryHeight: CGFloat = 1440
    private let thickness: CGFloat = 24

    // MARK: - isInMenuBarStrip

    @Test("cursor inside the top strip is detected")
    func inStripWhenAtTop() {
        // Cocoa y grows up: the strip is y in [1416, 1440].
        let mouse = CGPoint(x: 1280, y: 1430)
        #expect(CursorMonitor.isInMenuBarStrip(
            mouse: mouse, screens: [screen], menuBarThickness: thickness
        ))
    }

    @Test("cursor below the strip is not detected")
    func notInStripWhenBelow() {
        let mouse = CGPoint(x: 1280, y: 1000)
        #expect(!CursorMonitor.isInMenuBarStrip(
            mouse: mouse, screens: [screen], menuBarThickness: thickness
        ))
    }

    @Test("cursor in the strip counts anywhere along the bar, not just over items")
    func inStripAtFarEdge() {
        let mouse = CGPoint(x: 5, y: 1438)
        #expect(CursorMonitor.isInMenuBarStrip(
            mouse: mouse, screens: [screen], menuBarThickness: thickness
        ))
    }

    @Test("strip is matched per-screen on multi-display setups")
    func inStripOnSecondScreen() {
        let second = CGRect(x: 2560, y: 0, width: 1920, height: 1080)
        let mouse = CGPoint(x: 3000, y: 1075) // in the second screen's strip
        #expect(CursorMonitor.isInMenuBarStrip(
            mouse: mouse, screens: [screen, second], menuBarThickness: thickness
        ))
    }

    // MARK: - isOverMenuBarPopup

    /// A menu-bar-anchored dropdown: top edge just below the bar (CG y = 24),
    /// hanging down 300pt.
    private var anchoredPopup: CursorMonitor.WindowSnapshot {
        CursorMonitor.WindowSnapshot(layer: 101, bounds: CGRect(x: 100, y: 24, width: 320, height: 300))
    }

    /// Convert a CG (top-left) point into the Cocoa mouse location the monitor
    /// expects, so the tests read in the coordinate space the popup lives in.
    private func cocoaMouse(cgX: CGFloat, cgY: CGFloat) -> CGPoint {
        CGPoint(x: cgX, y: primaryHeight - cgY)
    }

    @Test("cursor over an anchored popup is detected")
    func overAnchoredPopup() {
        let mouse = cocoaMouse(cgX: 200, cgY: 150) // inside the popup
        #expect(CursorMonitor.isOverMenuBarPopup(
            mouse: mouse,
            screens: [screen],
            primaryHeight: primaryHeight,
            menuBarThickness: thickness,
            windows: [anchoredPopup]
        ))
    }

    @Test("cursor outside the popup bounds is not detected")
    func outsidePopupBounds() {
        let mouse = cocoaMouse(cgX: 200, cgY: 400) // below the popup (ends at 324)
        #expect(!CursorMonitor.isOverMenuBarPopup(
            mouse: mouse,
            screens: [screen],
            primaryHeight: primaryHeight,
            menuBarThickness: thickness,
            windows: [anchoredPopup]
        ))
    }

    @Test("a window not anchored to the menu bar is ignored")
    func nonAnchoredWindowIgnored() {
        // A floating panel mid-screen (top at CG y = 500), cursor inside it.
        let floating = CursorMonitor.WindowSnapshot(
            layer: 101, bounds: CGRect(x: 100, y: 500, width: 320, height: 300)
        )
        let mouse = cocoaMouse(cgX: 200, cgY: 600)
        #expect(!CursorMonitor.isOverMenuBarPopup(
            mouse: mouse,
            screens: [screen],
            primaryHeight: primaryHeight,
            menuBarThickness: thickness,
            windows: [floating]
        ))
    }

    @Test("a normal app window at layer 0 is ignored")
    func normalWindowIgnored() {
        let normal = CursorMonitor.WindowSnapshot(
            layer: 0, bounds: CGRect(x: 100, y: 24, width: 320, height: 300)
        )
        let mouse = cocoaMouse(cgX: 200, cgY: 150)
        #expect(!CursorMonitor.isOverMenuBarPopup(
            mouse: mouse,
            screens: [screen],
            primaryHeight: primaryHeight,
            menuBarThickness: thickness,
            windows: [normal]
        ))
    }

    @Test("no windows means no popup")
    func noWindows() {
        let mouse = cocoaMouse(cgX: 200, cgY: 150)
        #expect(!CursorMonitor.isOverMenuBarPopup(
            mouse: mouse,
            screens: [screen],
            primaryHeight: primaryHeight,
            menuBarThickness: thickness,
            windows: []
        ))
    }
}
