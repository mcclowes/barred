import AppKit
import Foundation
import os

@MainActor
protocol SectionDividing: AnyObject {
    var isSectionHidden: Bool { get }
    func setUp(onToggle: @escaping () -> Void)
    func expand()
    func collapse()
}

/// Manages an NSStatusItem that acts as a divider between visible and hidden
/// sections of the menu bar. Expanding its length pushes everything to its
/// left off-screen — the same technique used by Dozer and Hidden Bar.
@MainActor
final class SectionDivider: SectionDividing {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "SectionDivider")
    private var statusItem: NSStatusItem?
    private var isExpanded = false
    private var actionTarget: ActionTarget?
    // `nonisolated(unsafe)` because `deinit` is nonisolated in Swift 6 and
    // `NotificationCenter.removeObserver` is thread-safe for valid tokens.
    // The property is only *written* on the main actor, so there's no
    // race on the storage itself.
    // swiftlint:disable:next modifier_order
    private nonisolated(unsafe) var screenChangeObserver: NSObjectProtocol?

    /// The collapsed length — a small dot visible as a section separator.
    private static let collapsedLength: Double = 20

    /// Compute a safe expanded length that pushes items off-screen without
    /// causing the multi-GB memory leaks seen with excessively large values.
    /// Uses the widest connected screen rather than `NSScreen.main`, which
    /// tracks the key-window screen and may be narrower than the display
    /// that actually hosts the menu bar.
    private var expandedLength: Double {
        let widest = NSScreen.screens.map(\.frame.width).max() ?? 1000
        // 2x screen width handles ultrawide/5K displays; capped to avoid
        // the multi-GB memory leak seen with excessively large lengths.
        return min(widest * 2, 20000)
    }

    /// Create the divider status item. Must be called AFTER the main Barred
    /// status item exists, so the divider appears to its left.
    func setUp(onToggle: @escaping () -> Void) {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)

        let target = ActionTarget(action: onToggle)
        actionTarget = target

        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "line.vertical",
                accessibilityDescription: "Barred section divider"
            )
            button.image?.size = NSSize(width: 6, height: 16)
            button.imagePosition = .imageOnly
            button.target = target
            button.action = #selector(ActionTarget.performAction)
            button.sendAction(on: [.leftMouseUp])
        }

        statusItem = item

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // NotificationCenter delivers on the main queue, and this class
            // is @MainActor-isolated, so we can hop without further checks.
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }
    }

    deinit {
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
    }

    private func handleScreenChange() {
        guard isExpanded, let statusItem else { return }
        let length = expandedLength
        Self.logger.debug("Screen change — re-applying divider length to \(length)px")
        statusItem.length = length
    }

    /// Expand the divider to push items to its left off-screen.
    func expand() {
        guard let statusItem else {
            Self.logger.debug("expand() skipped — statusItem is nil (setUp not called yet?)")
            return
        }
        guard !isExpanded else { return }
        isExpanded = true
        let length = expandedLength
        Self.logger.debug("Expanding divider to \(length)px")
        statusItem.length = length
        if let button = statusItem.button {
            button.image = nil
            button.title = " "
        }
    }

    /// Collapse the divider to reveal hidden items.
    func collapse() {
        guard let statusItem else {
            Self.logger.debug("collapse() skipped — statusItem is nil")
            return
        }
        guard isExpanded else { return }
        isExpanded = false
        Self.logger.debug("Collapsing divider to \(Self.collapsedLength)px")
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

private class ActionTarget: NSObject {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func performAction() {
        action()
    }
}
