import AppKit
import Foundation

@MainActor @Observable
final class MenuBarController {
    static let shared = MenuBarController()

    let accessibilityService = AccessibilityService()
    private(set) var detector: MenuBarDetector!
    let preferencesStore = PreferencesStore()
    let sectionDivider = SectionDivider()
    private(set) var isBarredBarVisible = false
    private var autoHideTask: Task<Void, Never>?
    private var isTransitioning = false

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
        Task {
            try? await Task.sleep(for: .seconds(1))
            hideSection()
        }
    }

    func toggleBarredBar() {
        guard !isTransitioning else { return }

        isBarredBarVisible.toggle()

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
        sectionDivider.collapse()
    }

    // MARK: - Private

    private func hideSection() {
        isTransitioning = true
        sectionDivider.expand()
        isTransitioning = false
    }

    private func showSection() {
        isTransitioning = true
        sectionDivider.collapse()
        isTransitioning = false
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        let delay = preferences.autoHideDelay
        autoHideTask = Task {
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            isBarredBarVisible = false
            hideSection()
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }
}
