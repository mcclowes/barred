@testable import Barred
import Testing

@MainActor
private final class MockAccessibilityService: AccessibilityQuerying {
    var isTrusted = true
    func checkTrust() {}
    func requestTrust() {}
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo] { [] }
}

@MainActor
private final class MockDetector: MenuBarDetecting {
    var detectedItems: [MenuBarItem] = []
    var hasCompletedFirstScan = true
    var scanningStarted = false
    var scanningStopped = false

    func startScanning() { scanningStarted = true }
    func stopScanning() { scanningStopped = true }
    func scan() {}
    func waitForFirstScan() async {}
}

@MainActor
private final class MockSectionDivider: SectionDividing {
    var isSectionHidden = false
    var setUpCalled = false
    var expandCallCount = 0
    var collapseCallCount = 0

    func setUp() { setUpCalled = true }
    func expand() { expandCallCount += 1; isSectionHidden = true }
    func collapse() { collapseCallCount += 1; isSectionHidden = false }
}

@MainActor
struct MenuBarControllerTests {
    private func makeController(
        divider: MockSectionDivider = MockSectionDivider(),
        detector: MockDetector = MockDetector()
    ) -> (MenuBarController, MockSectionDivider, MockDetector) {
        let controller = MenuBarController(
            accessibilityService: MockAccessibilityService(),
            detector: detector,
            preferencesStore: PreferencesStore(),
            sectionDivider: divider
        )
        return (controller, divider, detector)
    }

    @Test("initially hidden bar is not visible")
    func initialState() {
        let (controller, _, _) = makeController()
        #expect(controller.isBarredBarVisible == false)
    }

    @Test("toggleBarredBar flips visibility")
    func toggle() {
        let (controller, _, _) = makeController()
        controller.toggleBarredBar()
        #expect(controller.isBarredBarVisible == true)
        controller.toggleBarredBar()
        #expect(controller.isBarredBarVisible == false)
    }

    @Test("toggle expands divider when hiding, collapses when showing")
    func toggleDividerBehaviour() {
        let (controller, divider, _) = makeController()

        controller.toggleBarredBar() // show
        #expect(divider.collapseCallCount == 1)

        controller.toggleBarredBar() // hide
        #expect(divider.expandCallCount == 1)
    }

    @Test("start sets up the section divider")
    func startSetUp() {
        let (controller, divider, _) = makeController()
        controller.start()
        #expect(divider.setUpCalled)
    }

    @Test("restoreAll stops scanning and collapses divider")
    func restoreAll() {
        let (controller, divider, detector) = makeController()
        controller.restoreAll()
        #expect(detector.scanningStopped)
        #expect(divider.collapseCallCount == 1)
    }

    @Test("detectedItems delegates to detector")
    func detectedItemsDelegation() {
        let (controller, _, _) = makeController()
        #expect(controller.detectedItems.isEmpty)
    }
}
