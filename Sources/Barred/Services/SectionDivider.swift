import AppKit
import Foundation
import os

@MainActor
protocol SectionDividing: AnyObject {
    var isSectionHidden: Bool { get }
    var hiddenBundleIdentifiers: Set<String> { get }
    var hidingUnavailableReason: String? { get }
    func setUp(onToggle: @escaping () -> Void)
    func expand() async -> Bool
    func collapse()
}

extension SectionDividing {
    var hidingUnavailableReason: String? {
        nil
    }

    var hiddenBundleIdentifiers: Set<String> {
        []
    }
}

/// Owns the section markers and selects hiding behavior for the running macOS.
@MainActor
final class SectionDivider: SectionDividing {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "SectionDivider")
    private var statusItem: NSStatusItem?
    private var startItem: NSStatusItem?
    private let nativeVisibility: NativeMenuBarVisibility?
    private var isExpanded = false
    private var generation = 0
    private var actionTarget: ActionTarget?
    // `nonisolated(unsafe)` because `deinit` is nonisolated in Swift 6 and
    // `NotificationCenter.removeObserver` is thread-safe for valid tokens.
    // The property is only *written* on the main actor, so there's no
    // race on the storage itself.
    // swiftlint:disable:next modifier_order
    private nonisolated(unsafe) var screenChangeObserver: NSObjectProtocol?

    /// The collapsed length, including space around the vertical separator.
    private static let collapsedLength: Double = 20
    private static let layoutSampleInterval: Duration = .milliseconds(100)
    private static let requiredStableLayoutSamples = 3
    private static let maximumLayoutSamples = 20

    static var usesBoundedSection: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
    }

    init(accessibilityService: any AccessibilityQuerying = AccessibilityService()) {
        self.nativeVisibility = Self.usesBoundedSection
            ? NativeMenuBarVisibility(accessibility: accessibilityService) : nil
    }

    static func makeDividerImage() -> NSImage {
        let size = NSSize(width: 6, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.withAlphaComponent(0.55).setFill()
            let line = NSRect(x: rect.midX - 0.5, y: rect.midY - 5, width: 1, height: 10)
            NSBezierPath(roundedRect: line, xRadius: 0.5, yRadius: 0.5).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Barred section divider"
        return image
    }

    static func setMarkersVisible(_ visible: Bool, markers: [NSStatusItem]) {
        for marker in markers {
            marker.length = visible ? collapsedLength : 0
            marker.button?.image = visible ? makeDividerImage() : nil
            marker.button?.title = ""
        }
    }

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
        item.autosaveName = "BarredHiddenSectionEnd"

        let target = ActionTarget(action: onToggle)
        actionTarget = target

        if let button = item.button {
            button.image = Self.makeDividerImage()
            button.imagePosition = .imageOnly
            button.target = target
            button.action = #selector(ActionTarget.performAction)
            button.sendAction(on: [.leftMouseUp])
        }

        statusItem = item

        if nativeVisibility != nil {
            let start = NSStatusBar.system.statusItem(withLength: Self.collapsedLength)
            start.autosaveName = "BarredHiddenSectionStart"
            start.button?.image = Self.makeDividerImage()
            start.button?.target = target
            start.button?.action = #selector(ActionTarget.performAction)
            start.button?.toolTip = "Command-drag icons between the two lines to hide them"
            startItem = start
        }
        item.button?.toolTip = nativeVisibility == nil
            ? "Command-drag icons left of this line to hide them"
            : "Command-drag icons between the two lines to hide them"

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
        guard nativeVisibility == nil, isExpanded, let statusItem else { return }
        let length = expandedLength
        Self.logger.debug("Screen change — re-applying divider length to \(length)px")
        statusItem.length = length
    }

    /// Hide the section using native visibility on macOS 27 or length expansion on older systems.
    func expand() async -> Bool {
        guard let statusItem else {
            Self.logger.debug("expand() skipped — statusItem is nil (setUp not called yet?)")
            return false
        }
        guard !isExpanded else { return true }
        generation += 1
        let request = generation
        if let nativeVisibility {
            guard let startItem,
                  let (first, second) = await settledMarkerFrames(request: request),
                  request == generation
            else { return false }
            let hidden = await nativeVisibility.hide(between: first, and: second)
            guard request == generation else { return false }
            isExpanded = hidden
            if hidden {
                Self.setMarkersVisible(false, markers: [startItem, statusItem])
            }
            return hidden
        }
        isExpanded = true
        let length = expandedLength
        Self.logger.debug("Expanding divider to \(length)px")
        statusItem.length = length
        if let button = statusItem.button {
            button.image = nil
            button.title = " "
        }
        return true
    }

    private func settledMarkerFrames(request: Int) async -> (CGRect, CGRect)? {
        var previous: [CGRect] = []
        var stableSamples = 0
        // Restoring the assertion and marker widths reflows asynchronously. Reading
        // immediately can select a different section on every rapid toggle.
        for _ in 0 ..< Self.maximumLayoutSamples {
            do {
                try await Task.sleep(for: Self.layoutSampleInterval)
            } catch {
                return nil
            }
            guard request == generation, let startItem, let statusItem,
                  let first = Self.screenFrame(of: startItem),
                  let second = Self.screenFrame(of: statusItem)
            else { return nil }
            let frames = [first, second]
            let left = first.midX < second.midX ? first : second
            let right = first.midX < second.midX ? second : first
            guard left.width > 0, right.width > 0, left.maxX <= right.minX,
                  left.minY == right.minY
            else {
                previous = []
                stableSamples = 0
                continue
            }
            stableSamples = frames == previous ? stableSamples + 1 : 1
            if stableSamples >= Self.requiredStableLayoutSamples {
                return (first, second)
            }
            previous = frames
        }
        return nil
    }

    /// Collapse the divider to reveal hidden items.
    func collapse() {
        generation += 1
        nativeVisibility?.show()
        guard let statusItem else {
            Self.logger.debug("collapse() skipped — statusItem is nil")
            return
        }
        isExpanded = false
        Self.logger.debug("Collapsing divider to \(Self.collapsedLength)px")
        Self.setMarkersVisible(true, markers: [startItem, statusItem].compactMap(\.self))
    }

    var isSectionHidden: Bool {
        isExpanded
    }

    var hiddenBundleIdentifiers: Set<String> {
        nativeVisibility?.hiddenBundleIdentifiers ?? []
    }

    var hidingUnavailableReason: String? {
        nativeVisibility?.unavailableReason
    }

    private static func screenFrame(of item: NSStatusItem) -> CGRect? {
        guard let button = item.button, let window = button.window,
              let primary = NSScreen.screens.first
        else { return nil }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return CGRect(x: frame.minX, y: primary.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }

    #if DEBUG
        func diagnosticSnapshot(label: String) -> [String: Any] {
            func rect(_ frame: CGRect?) -> [Double] {
                guard let frame else { return [] }
                return [frame.minX, frame.minY, frame.width, frame.height]
            }
            return [
                "label": label,
                "start": rect(startItem.flatMap(Self.screenFrame)),
                "end": rect(statusItem.flatMap(Self.screenFrame)),
                "hidden": hiddenBundleIdentifiers.sorted(),
                "error": hidingUnavailableReason ?? ""
            ]
        }
    #endif
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
