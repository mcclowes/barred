import AppKit
import Foundation

@MainActor @Observable
final class MenuBarController {
    static let shared = MenuBarController()

    let accessibilityService = AccessibilityService()
    private(set) var detector: MenuBarDetector!
    let preferencesStore = PreferencesStore()
    private let overlayWindow = OverlayWindow()
    private(set) var isBarmanBarVisible = false
    private var autoHideTimer: Timer?

    var detectedItems: [MenuBarItem] {
        detector?.detectedItems ?? []
    }

    var preferences: UserPreferences {
        get { preferencesStore.preferences }
        set { preferencesStore.preferences = newValue }
    }

    init() {
        detector = MenuBarDetector(accessibilityService: accessibilityService)
        detector.startScanning()
        updateOverlay()
    }

    func toggleBarmanBar() {
        isBarmanBarVisible.toggle()

        if isBarmanBarVisible {
            revealHiddenItems()
            scheduleAutoHide()
        } else {
            coverHiddenItems()
            cancelAutoHide()
        }
    }

    func updateOverlay() {
        guard !isBarmanBarVisible else { return }
        coverHiddenItems()
    }

    func setVisibility(_ visibility: ItemVisibility, for item: MenuBarItem) {
        preferencesStore.preferences.setVisibility(visibility, for: item)
        preferencesStore.save()
        updateOverlay()
    }

    func visibility(for item: MenuBarItem) -> ItemVisibility {
        preferences.visibility(for: item)
    }

    // MARK: - Coordinate conversion

    /// AX/CGWindow coordinates: origin top-left, y increases downward.
    /// NSWindow coordinates: origin bottom-left, y increases upward.
    /// This converts an AX-origin rect to NSWindow coordinates.
    private func convertToScreenCoordinates(axRect: CGRect) -> CGRect {
        // Total height across all screens (from the primary screen)
        guard let primaryScreen = NSScreen.screens.first else { return axRect }
        let screenHeight = primaryScreen.frame.height

        return CGRect(
            x: axRect.origin.x,
            y: screenHeight - axRect.origin.y - axRect.height,
            width: axRect.width,
            height: axRect.height
        )
    }

    private func menuBarFrame(covering items: [MenuBarItem]) -> CGRect? {
        guard !items.isEmpty else { return nil }

        let minX = items.map(\.frame.origin.x).min() ?? 0
        let maxX = items.map { $0.frame.origin.x + $0.frame.width }.max() ?? 0
        let minY = items.map(\.frame.origin.y).min() ?? 0
        let itemHeight = items.map(\.frame.height).max() ?? 24

        // AX coordinates: top-left origin
        let axRect = CGRect(
            x: minX - 4,
            y: minY,
            width: (maxX - minX) + 8,
            height: itemHeight
        )

        let screenRect = convertToScreenCoordinates(axRect: axRect)
        print("[Barman] Overlay: AX rect \(axRect) -> screen rect \(screenRect)")
        return screenRect
    }

    // MARK: - Private

    private func coverHiddenItems() {
        let hiddenItems = detectedItems.filter { item in
            let vis = visibility(for: item)
            return vis == .hidden || vis == .barmanBar
        }

        guard let frame = menuBarFrame(covering: hiddenItems) else {
            overlayWindow.hide()
            return
        }

        overlayWindow.cover(frame: frame)
    }

    private func revealHiddenItems() {
        let hiddenOnlyItems = detectedItems.filter { visibility(for: $0) == .hidden }

        guard let frame = menuBarFrame(covering: hiddenOnlyItems) else {
            overlayWindow.hide()
            return
        }

        overlayWindow.animateReveal(to: frame)
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: preferences.autoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isBarmanBarVisible = false
                self?.coverHiddenItems()
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }
}
