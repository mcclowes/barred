import AppKit
import Foundation

@MainActor @Observable
final class MenuBarController {
    let accessibilityService: AccessibilityQuerying
    let detector: MenuBarDetecting
    let preferencesStore: PreferencesStoring
    let sectionDivider: SectionDividing
    private(set) var isBarredBarVisible = false
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
        sectionDivider: SectionDividing = SectionDivider()
    ) {
        self.accessibilityService = accessibilityService
        self.preferencesStore = preferencesStore
        self.sectionDivider = sectionDivider
        self.detector = detector ?? MenuBarDetector(accessibilityService: accessibilityService)
        self.detector.startScanning()
    }

    /// Call after the main Barred status item has been created, so the
    /// divider appears to its left in the menu bar.
    func start() {
        sectionDivider.setUp()

        Task {
            await detector.waitForFirstScan()
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
        detector.stopScanning()
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
