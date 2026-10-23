import AppKit
import Foundation
import os

@MainActor @Observable
final class MenuBarController {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "MenuBarController")
    let accessibilityService: AccessibilityQuerying
    let detector: MenuBarDetecting
    let preferencesStore: PreferencesStoring
    let sectionDivider: SectionDividing
    let itemMover: MenuBarItemMoving
    let cursorMonitor: CursorMonitoring
    private(set) var isBarredBarVisible = false
    private(set) var isMovingItem = false
    private(set) var hidingError: String?
    private var autoHideTask: Task<Void, Never>?
    private var visibilityGeneration = 0
    private let idleTickInterval: Duration

    var detectedItems: [MenuBarItem] {
        let hiddenBundles = sectionDivider.hiddenBundleIdentifiers
        return detector.detectedItems.map { detected in
            var item = detected
            item.isManagedHidden = item.bundleIdentifier.map(hiddenBundles.contains) ?? false
            return item
        }
    }

    var preferences: UserPreferences {
        get { preferencesStore.preferences }
        set { preferencesStore.preferences = newValue }
    }

    init(
        accessibilityService: AccessibilityQuerying = AccessibilityService(),
        detector: MenuBarDetecting? = nil,
        preferencesStore: PreferencesStoring = PreferencesStore(),
        sectionDivider: SectionDividing? = nil,
        itemMover: MenuBarItemMoving = MenuBarItemMover(),
        cursorMonitor: CursorMonitoring = CursorMonitor(),
        idleTickInterval: Duration = .milliseconds(200)
    ) {
        self.accessibilityService = accessibilityService
        self.preferencesStore = preferencesStore
        self.sectionDivider = sectionDivider ?? SectionDivider(accessibilityService: accessibilityService)
        self.itemMover = itemMover
        self.cursorMonitor = cursorMonitor
        self.idleTickInterval = idleTickInterval
        self.detector = detector ?? MenuBarDetector(accessibilityService: accessibilityService)
    }

    /// Call after the main Barred status item has been created, so the
    /// divider appears to its left in the menu bar.
    func start() {
        detector.startScanning()

        sectionDivider.setUp { [weak self] in
            Task { await self?.toggleBarredBar() }
        }

        let initialGeneration = visibilityGeneration
        Task {
            await detector.waitForFirstScan()
            guard initialGeneration == visibilityGeneration else { return }
            await hideSection()
        }
    }

    func toggleBarredBar() async {
        if !isBarredBarVisible {
            visibilityGeneration += 1
            isBarredBarVisible = true
            hidingError = nil
            showSection()
            scheduleAutoHide()
        } else {
            cancelAutoHide()
            await hideSection()
        }
    }

    func restoreAll() {
        visibilityGeneration += 1
        cancelAutoHide()
        detector.stopScanning()
        sectionDivider.collapse()
    }

    /// Reorder a visible menu bar item by synthesizing a Command-drag gesture.
    /// `items` is the slice currently displayed in the Settings list (sorted
    /// left-to-right by x). `source` and `destination` follow SwiftUI's
    /// `.onMove` semantics: `destination` is the insertion index in the
    /// original ordering.
    func moveItem(from source: IndexSet, to destination: Int, in items: [MenuBarItem]) async {
        guard let sourceIndex = source.first,
              sourceIndex >= 0, sourceIndex < items.count,
              destination >= 0, destination <= items.count,
              destination != sourceIndex, destination != sourceIndex + 1
        else {
            Self.logger.debug("moveItem no-op (source: \(source), destination: \(destination))")
            return
        }

        let sourceItem = items[sourceIndex]
        guard sourceItem.frame.width > 0, sourceItem.frame.height > 0 else {
            Self.logger.debug("moveItem skipped — source item has zero frame")
            return
        }

        let sourcePoint = CGPoint(x: sourceItem.frame.midX, y: sourceItem.frame.midY)
        let destinationX = Self.dropX(
            forMovingItemAt: sourceIndex,
            to: destination,
            in: items
        )
        let destinationPoint = CGPoint(x: destinationX, y: sourceItem.frame.midY)

        isMovingItem = true
        defer { isMovingItem = false }

        await itemMover.performDrag(from: sourcePoint, to: destinationPoint)

        // Let the OS finish animating the reshuffle, then refresh detection.
        try? await Task.sleep(for: .milliseconds(300))
        await detector.scan()
    }

    /// Compute the drop x-coordinate that will place the moving item into the
    /// `destination` slot. `destination` is in the original (pre-remove) list
    /// indexing, matching SwiftUI `.onMove`.
    static func dropX(
        forMovingItemAt sourceIndex: Int,
        to destination: Int,
        in items: [MenuBarItem]
    ) -> Double {
        let sourceItem = items[sourceIndex]
        let halfWidth = sourceItem.frame.width / 2
        let gap: Double = 4

        if destination >= items.count {
            // Dropping past the rightmost item. Skip the source itself if
            // it's currently the rightmost.
            let rightmost = items.last(where: { $0.id != sourceItem.id }) ?? sourceItem
            return rightmost.frame.maxX + halfWidth + gap
        }

        if destination == 0 {
            // Dropping before the leftmost item. Skip the source itself if
            // it's currently the leftmost.
            let leftmost = items.first(where: { $0.id != sourceItem.id }) ?? sourceItem
            return leftmost.frame.minX - halfWidth - gap
        }

        // Drop just before `items[destination]` in the original ordering so
        // the OS inserts the source item into that slot.
        let target = items[destination]
        return target.frame.minX - halfWidth - gap
    }

    // MARK: - Private

    private func hideSection() async {
        visibilityGeneration += 1
        let request = visibilityGeneration
        isBarredBarVisible = false
        let hidden = await sectionDivider.expand()
        guard request == visibilityGeneration else { return }
        isBarredBarVisible = !hidden
        hidingError = hidden ? nil : sectionDivider.hidingUnavailableReason
            ?? "Barred couldn’t hide this section. Check Accessibility access and try again."
    }

    private func showSection() {
        sectionDivider.collapse()
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        let delay = preferences.autoHideDelay
        let tick = idleTickInterval
        autoHideTask = Task { [weak self] in
            await self?.runIdleCountdown(delay: delay, tick: tick)
            guard let self, !Task.isCancelled, isBarredBarVisible else { return }
            await hideSection()
        }
    }

    /// Polls the cursor and `isMovingItem` on each tick. The "idle" clock resets
    /// while the user is dragging an item, has the cursor anywhere in the menu
    /// bar strip, or is interacting with an open menu-bar dropdown — so the bar
    /// only auto-hides after `delay` seconds of true inactivity.
    private func runIdleCountdown(delay: TimeInterval, tick: Duration) async {
        let clock = ContinuousClock()
        var idleStart = clock.now
        let deadline: Duration = .seconds(delay)
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: tick)
            } catch {
                return
            }
            guard isBarredBarVisible else { return }
            if isMovingItem
                || cursorMonitor.isInMenuBarStrip()
                || cursorMonitor.isOverMenuBarPopup()
            {
                idleStart = clock.now
                continue
            }
            if clock.now - idleStart >= deadline {
                return
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
