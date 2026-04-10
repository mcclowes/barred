import AppKit
import CoreGraphics
import os

@MainActor
protocol MenuBarItemMoving: AnyObject {
    func performDrag(from source: CGPoint, to destination: CGPoint) async
}

/// Synthesizes a Command-drag gesture to reorder a menu bar item, mirroring
/// the manual gesture a user would perform. macOS doesn't expose a public API
/// to programmatically move another app's status item, so we drive the input
/// layer directly via `CGEvent`.
///
/// Requires Accessibility permission — the same grant that powers
/// `AccessibilityService`.
@MainActor
final class MenuBarItemMover: MenuBarItemMoving {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "MenuBarItemMover")

    /// `kVK_Command` from Carbon. Hard-coded to avoid a Carbon import.
    private static let commandKeyCode: CGKeyCode = 0x37

    /// Number of intermediate drag events between source and destination.
    /// Enough to feel like a real drag to macOS, not so many that the gesture
    /// takes noticeably long.
    private static let dragSteps = 25

    func performDrag(from source: CGPoint, to destination: CGPoint) async {
        Self.logger.debug(
            "Cmd-drag from (\(source.x), \(source.y)) to (\(destination.x), \(destination.y))"
        )

        let eventSource = CGEventSource(stateID: .combinedSessionState)

        postCommandKey(down: true, source: eventSource)
        await sleep(milliseconds: 50)

        postMouseEvent(
            type: .leftMouseDown,
            position: source,
            source: eventSource
        )
        await sleep(milliseconds: 80)

        for step in 1 ... Self.dragSteps {
            let progress = Double(step) / Double(Self.dragSteps)
            let point = CGPoint(
                x: source.x + (destination.x - source.x) * progress,
                y: source.y + (destination.y - source.y) * progress
            )
            postMouseEvent(
                type: .leftMouseDragged,
                position: point,
                source: eventSource
            )
            await sleep(milliseconds: 12)
        }

        await sleep(milliseconds: 40)

        postMouseEvent(
            type: .leftMouseUp,
            position: destination,
            source: eventSource
        )
        await sleep(milliseconds: 50)

        postCommandKey(down: false, source: eventSource)
    }

    // MARK: - Event helpers

    private func postCommandKey(down: Bool, source: CGEventSource?) {
        guard let event = CGEvent(
            keyboardEventSource: source,
            virtualKey: Self.commandKeyCode,
            keyDown: down
        ) else {
            Self.logger.error("Failed to create Cmd key event (down: \(down))")
            return
        }
        event.post(tap: .cghidEventTap)
    }

    private func postMouseEvent(
        type: CGEventType,
        position: CGPoint,
        source: CGEventSource?
    ) {
        guard let event = CGEvent(
            mouseEventSource: source,
            mouseType: type,
            mouseCursorPosition: position,
            mouseButton: .left
        ) else {
            Self.logger.error("Failed to create mouse event \(type.rawValue)")
            return
        }
        event.flags = .maskCommand
        event.post(tap: .cghidEventTap)
    }

    private func sleep(milliseconds: Int) async {
        try? await Task.sleep(for: .milliseconds(milliseconds))
    }
}
