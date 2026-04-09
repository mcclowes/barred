@testable import Barred
import Testing

@MainActor
private final class MockAccessibilityService: AccessibilityQuerying {
    var isTrusted = true
    func checkTrust() {}
    func requestTrust() {}
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo] {
        []
    }
}

@MainActor
private final class MockDetector: MenuBarDetecting {
    var detectedItems: [MenuBarItem] = []
    var hasCompletedFirstScan = true
    var scanningStarted = false
    var scanningStopped = false

    func startScanning() {
        scanningStarted = true
    }

    func stopScanning() {
        scanningStopped = true
    }

    func scan() {}
    func waitForFirstScan() async {}
}

@MainActor
private final class MockSectionDivider: SectionDividing {
    var isSectionHidden = false
    var setUpCalled = false
    var expandCallCount = 0
    var collapseCallCount = 0

    func setUp(onToggle _: @escaping () -> Void) {
        setUpCalled = true
    }

    func expand() {
        expandCallCount += 1
        isSectionHidden = true
    }

    func collapse() {
        collapseCallCount += 1
        isSectionHidden = false
    }
}

@MainActor
struct MenuBarControllerTests {
    private struct TestHarness {
        let controller: MenuBarController
        let divider: MockSectionDivider
        let detector: MockDetector
    }

    private func makeController(
        divider: MockSectionDivider = MockSectionDivider(),
        detector: MockDetector = MockDetector()
    ) -> TestHarness {
        let controller = MenuBarController(
            accessibilityService: MockAccessibilityService(),
            detector: detector,
            preferencesStore: PreferencesStore(),
            sectionDivider: divider
        )
        return TestHarness(controller: controller, divider: divider, detector: detector)
    }

    @Test("initially hidden bar is not visible")
    func initialState() {
        let harness = makeController()
        #expect(harness.controller.isBarredBarVisible == false)
    }

    @Test("toggleBarredBar flips visibility")
    func toggle() {
        let harness = makeController()
        harness.controller.toggleBarredBar()
        #expect(harness.controller.isBarredBarVisible == true)
        harness.controller.toggleBarredBar()
        #expect(harness.controller.isBarredBarVisible == false)
    }

    @Test("toggle expands divider when hiding, collapses when showing")
    func toggleDividerBehaviour() {
        let harness = makeController()

        harness.controller.toggleBarredBar() // show
        #expect(harness.divider.collapseCallCount == 1)

        harness.controller.toggleBarredBar() // hide
        #expect(harness.divider.expandCallCount == 1)
    }

    @Test("start sets up the section divider")
    func startSetUp() {
        let harness = makeController()
        harness.controller.start()
        #expect(harness.divider.setUpCalled)
    }

    @Test("restoreAll stops scanning and collapses divider")
    func restoreAll() {
        let harness = makeController()
        harness.controller.restoreAll()
        #expect(harness.detector.scanningStopped)
        #expect(harness.divider.collapseCallCount == 1)
    }

    @Test("detectedItems delegates to detector")
    func detectedItemsDelegation() {
        let harness = makeController()
        #expect(harness.controller.detectedItems.isEmpty)
    }
}
