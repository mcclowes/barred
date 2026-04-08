import AppKit
import Foundation

/// Manages an NSStatusItem that acts as a divider between visible and hidden
/// sections of the menu bar. Expanding its length pushes everything to its
/// left off-screen — the same technique used by Dozer and Hidden Bar.
@MainActor
final class SectionDivider {
    private let statusItem: NSStatusItem
    private var isExpanded = false

    /// The collapsed length — a small dot visible as a section separator.
    private static let collapsedLength: CGFloat = 20

    /// Compute a safe expanded length that pushes items off-screen without
    /// causing the multi-GB memory leaks seen with excessively large values.
    private var expandedLength: CGFloat {
        guard let screen = NSScreen.main else { return 2000 }
        let screenWidth = screen.frame.width
        return max(500, min(screenWidth + 200, 4000))
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "line.vertical",
                accessibilityDescription: "Barman section divider"
            )
            button.image?.size = NSSize(width: 6, height: 16)
            button.imagePosition = .imageOnly
            button.action = #selector(AppDelegate.toggleBarmanBarFromDivider)
            button.sendAction(on: [.leftMouseUp])
        }
    }

    /// Expand the divider to push items to its left off-screen.
    func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        statusItem.length = expandedLength
        if let button = statusItem.button {
            button.image = nil
        }
    }

    /// Collapse the divider to reveal hidden items.
    func collapse() {
        guard isExpanded else { return }
        isExpanded = false
        statusItem.length = Self.collapsedLength
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "line.vertical",
                accessibilityDescription: "Barman section divider"
            )
            button.image?.size = NSSize(width: 6, height: 16)
        }
    }

    var isSectionHidden: Bool {
        isExpanded
    }
}
