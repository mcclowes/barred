import AppKit
import Foundation

@MainActor
protocol SectionDividing: AnyObject {
    var isSectionHidden: Bool { get }
    func setUp()
    func expand()
    func collapse()
}

/// Manages an NSStatusItem that acts as a divider between visible and hidden
/// sections of the menu bar. Expanding its length pushes everything to its
/// left off-screen — the same technique used by Dozer and Hidden Bar.
@MainActor
final class SectionDivider: SectionDividing {
    private var statusItem: NSStatusItem?
    private var isExpanded = false

    /// The collapsed length — a small dot visible as a section separator.
    private static let collapsedLength: Double = 20

    /// Compute a safe expanded length that pushes items off-screen without
    /// causing the multi-GB memory leaks seen with excessively large values.
    private var expandedLength: Double {
        guard let screen = NSScreen.main else { return 2000 }
        let screenWidth = screen.frame.width
        // Use 2x screen width to handle ultrawide/5K displays, capped to
        // avoid the memory leak that occurs with extremely large values.
        return min(screenWidth * 2, 10000)
    }

    /// Create the divider status item. Must be called AFTER the main Barred
    /// status item exists, so the divider appears to its left.
    func setUp() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "line.vertical",
                accessibilityDescription: "Barred section divider"
            )
            button.image?.size = NSSize(width: 6, height: 16)
            button.imagePosition = .imageOnly
            button.action = #selector(AppDelegate.toggleBarredBarFromDivider)
            button.sendAction(on: [.leftMouseUp])
        }

        statusItem = item
    }

    /// Expand the divider to push items to its left off-screen.
    func expand() {
        guard let statusItem else {
            #if DEBUG
            print("[Barred] expand() skipped — statusItem is nil (setUp not called yet?)")
            #endif
            return
        }
        guard !isExpanded else { return }
        isExpanded = true
        let length = expandedLength
        #if DEBUG
        print("[Barred] Expanding divider to \(length)px")
        #endif
        statusItem.length = length
        if let button = statusItem.button {
            button.image = nil
            button.title = " "
        }
    }

    /// Collapse the divider to reveal hidden items.
    func collapse() {
        guard let statusItem else {
            #if DEBUG
            print("[Barred] collapse() skipped — statusItem is nil")
            #endif
            return
        }
        guard isExpanded else { return }
        isExpanded = false
        #if DEBUG
        print("[Barred] Collapsing divider to \(Self.collapsedLength)px")
        #endif
        statusItem.length = Self.collapsedLength
        if let button = statusItem.button {
            button.title = ""
            button.image = NSImage(
                systemSymbolName: "line.vertical",
                accessibilityDescription: "Barred section divider"
            )
            button.image?.size = NSSize(width: 6, height: 16)
        }
    }

    var isSectionHidden: Bool {
        isExpanded
    }
}
