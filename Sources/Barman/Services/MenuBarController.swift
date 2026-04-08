import AppKit
import Foundation

@MainActor @Observable
final class MenuBarController {
    static let shared = MenuBarController()

    let accessibilityService = AccessibilityService()
    private(set) var detector: MenuBarDetector!
    let preferencesStore = PreferencesStore()
    let sectionDivider = SectionDivider()
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

        // Hide the section after first scan
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.hideSection()
        }
    }

    func toggleBarmanBar() {
        isBarmanBarVisible.toggle()

        if isBarmanBarVisible {
            showSection()
            scheduleAutoHide()
        } else {
            hideSection()
            cancelAutoHide()
        }
    }

    func restoreAll() {
        sectionDivider.collapse()
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
        autoHideTimer = Timer.scheduledTimer(
            withTimeInterval: preferences.autoHideDelay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isBarmanBarVisible = false
                self?.hideSection()
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }
}
