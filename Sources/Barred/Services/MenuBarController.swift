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
    }

    /// Call after the main Barred status item has been created, so the
    /// divider appears to its left in the menu bar.
    func start() {
        sectionDivider.setUp()

        // Hide the section after first scan completes
        Task {
            try? await Task.sleep(for: .seconds(1))
            hideSection()
        }
    }

    func toggleBarredBar() {
        isBarredBarVisible.toggle()
        #if DEBUG
        print("[Barred] toggleBarredBar → isBarredBarVisible=\(isBarredBarVisible)")
        #endif

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
        sectionDivider.expand()
    }

    private func showSection() {
        sectionDivider.collapse()
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
