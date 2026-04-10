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
    private(set) var isBarredBarVisible = false
    private(set) var isMovingItem = false
    private var autoHideTask: Task<Void, Never>?

    var detectedItems: [MenuBarItem] {
        detector.detectedItems
    }

    var preferences: UserPreferences {
        get { preferencesStore.preferences }
        set { preferencesStore.preferences = newValue }
    }

    init(
        accessibilityService: AccessibilityQuerying = AccessibilityService(),
        detector: MenuBarDetecting? = nil,
        preferencesStore: PreferencesStoring = PreferencesStore(),
        sectionDivider: SectionDividing = SectionDivider(),
        itemMover: MenuBarItemMoving = MenuBarItemMover()
    ) {
        self.accessibilityService = accessibilityService
        self.preferencesStore = preferencesStore
        self.sectionDivider = sectionDivider
        self.itemMover = itemMover
        self.detector = detector ?? MenuBarDetector(accessibilityService: accessibilityService)
    }

    /// Call after the main Barred status item has been created, so the
    /// divider appears to its left in the menu bar.
    func start() {
        detector.startScanning()

        sectionDivider.setUp { [weak self] in
            self?.toggleBarredBar()
        }

        Task {
            await detector.waitForFirstScan()
            hideSection()
        }
    }

    func toggleBarredBar() {
        isBarredBarVisible.toggle()
        Self.logger.debug("toggleBarredBar → isBarredBarVisible=\(self.isBarredBarVisible)")

        if isBarredBarVisible {
            showSection()
            scheduleAutoHide()
        } else {
            cancelAutoHide()
            hideSection()
        }
    }

    func restoreAll() {
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

    private func hideSection() {
        sectionDivider.expand()
    }

    private func showSection() {
        sectionDivider.collapse()
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        let delay = preferences.autoHideDelay
        autoHideTask = Task {
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard isBarredBarVisible else { return }
            isBarredBarVisible = false
            hideSection()
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
