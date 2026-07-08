import AppKit
@testable import Barred
import Foundation
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
private final class MockItemMover: MenuBarItemMoving {
    var performDragCallCount = 0
    var lastSource: CGPoint?
    var lastDestination: CGPoint?

    func performDrag(from source: CGPoint, to destination: CGPoint) async {
        performDragCallCount += 1
        lastSource = source
        lastDestination = destination
    }
}

@MainActor
private final class MockCursorMonitor: CursorMonitoring {
    var inStrip = false
    var overPopup = false

    func isInMenuBarStrip() -> Bool {
        inStrip
    }

    func isOverMenuBarPopup() -> Bool {
        overPopup
    }
}

@MainActor
struct MenuBarControllerTests {
    private struct TestHarness {
        let controller: MenuBarController
        let divider: MockSectionDivider
        let detector: MockDetector
        let mover: MockItemMover
        let cursorMonitor: MockCursorMonitor
    }

    private func makeController(
        divider: MockSectionDivider = MockSectionDivider(),
        detector: MockDetector = MockDetector(),
        mover: MockItemMover = MockItemMover(),
        cursorMonitor: MockCursorMonitor = MockCursorMonitor(),
        autoHideDelay: TimeInterval? = nil,
        idleTickInterval: Duration = .milliseconds(200)
    ) -> TestHarness {
        let prefsStore = PreferencesStore()
        if let autoHideDelay {
            prefsStore.preferences.autoHideDelay = autoHideDelay
        }
        let controller = MenuBarController(
            accessibilityService: MockAccessibilityService(),
            detector: detector,
            preferencesStore: prefsStore,
            sectionDivider: divider,
            itemMover: mover,
            cursorMonitor: cursorMonitor,
            idleTickInterval: idleTickInterval
        )
        return TestHarness(
            controller: controller,
            divider: divider,
            detector: detector,
            mover: mover,
            cursorMonitor: cursorMonitor
        )
    }

    private func makeItem(
        id: String,
        x: Double,
        width: Double = 24
    ) -> MenuBarItem {
        MenuBarItem(
            pid: 1,
            appName: id,
            bundleIdentifier: "com.test.\(id)",
            title: id,
            windowID: 0,
            frame: CGRect(x: x, y: 0, width: width, height: 24),
            itemIndex: 0,
            axElement: nil
        )
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

    @Test("start sets up the section divider and begins scanning")
    func startSetUp() {
        let harness = makeController()
        #expect(harness.detector.scanningStarted == false)
        harness.controller.start()
        #expect(harness.divider.setUpCalled)
        #expect(harness.detector.scanningStarted == true)
    }

    @Test("init does not start scanning")
    func initDoesNotScan() {
        let harness = makeController()
        #expect(harness.detector.scanningStarted == false)
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

    // MARK: - moveItem

    @Test("moveItem forward drops just before destination slot")
    func moveItemForward() async {
        let harness = makeController()
        let items = [
            makeItem(id: "A", x: 100),
            makeItem(id: "B", x: 140),
            makeItem(id: "C", x: 180),
            makeItem(id: "D", x: 220),
            makeItem(id: "E", x: 260),
        ]
        // Move A (index 0) to slot 4 → A should land between D and E.
        await harness.controller.moveItem(from: IndexSet(integer: 0), to: 4, in: items)

        #expect(harness.mover.performDragCallCount == 1)
        // Source center of A is (112, 12).
        #expect(harness.mover.lastSource == CGPoint(x: 112, y: 12))
        // Destination x = E.minX - halfWidth(12) - gap(4) = 260 - 16 = 244.
        #expect(harness.mover.lastDestination?.x == 244)
    }

    @Test("moveItem backward drops before destination slot")
    func moveItemBackward() async {
        let harness = makeController()
        let items = [
            makeItem(id: "A", x: 100),
            makeItem(id: "B", x: 140),
            makeItem(id: "C", x: 180),
            makeItem(id: "D", x: 220),
            makeItem(id: "E", x: 260),
        ]
        // Move D (index 3) to slot 1 → D should land between A and B.
        await harness.controller.moveItem(from: IndexSet(integer: 3), to: 1, in: items)

        #expect(harness.mover.performDragCallCount == 1)
        // Destination x = B.minX - halfWidth(12) - gap(4) = 140 - 16 = 124.
        #expect(harness.mover.lastDestination?.x == 124)
    }

    @Test("moveItem to the end drops past rightmost item")
    func moveItemToEnd() async {
        let harness = makeController()
        let items = [
            makeItem(id: "A", x: 100),
            makeItem(id: "B", x: 140),
            makeItem(id: "C", x: 180),
        ]
        // Move A (index 0) to end (slot 3) → past C.
        await harness.controller.moveItem(from: IndexSet(integer: 0), to: 3, in: items)

        #expect(harness.mover.performDragCallCount == 1)
        // C.maxX = 204, + halfWidth(12) + gap(4) = 220.
        #expect(harness.mover.lastDestination?.x == 220)
    }

    @Test("moveItem to the start drops before leftmost item")
    func moveItemToStart() async {
        let harness = makeController()
        let items = [
            makeItem(id: "A", x: 100),
            makeItem(id: "B", x: 140),
            makeItem(id: "C", x: 180),
        ]
        // Move C (index 2) to slot 0 → before A.
        await harness.controller.moveItem(from: IndexSet(integer: 2), to: 0, in: items)

        #expect(harness.mover.performDragCallCount == 1)
        // A.minX = 100, - halfWidth(12) - gap(4) = 84.
        #expect(harness.mover.lastDestination?.x == 84)
    }

    @Test("moveItem no-ops for same slot")
    func moveItemSameSlot() async {
        let harness = makeController()
        let items = [
            makeItem(id: "A", x: 100),
            makeItem(id: "B", x: 140),
        ]
        // Destination == source is a no-op.
        await harness.controller.moveItem(from: IndexSet(integer: 0), to: 0, in: items)
        // Destination == source + 1 is also a no-op (would insert before the next
        // item, leaving the order unchanged).
        await harness.controller.moveItem(from: IndexSet(integer: 0), to: 1, in: items)

        #expect(harness.mover.performDragCallCount == 0)
    }

    // MARK: - auto-hide

    @Test("auto-hide fires after delay when cursor is idle")
    func autoHideFiresWhenIdle() async throws {
        let harness = makeController(
            autoHideDelay: 0.1,
            idleTickInterval: .milliseconds(20)
        )
        harness.cursorMonitor.inStrip = false
        harness.controller.toggleBarredBar()
        #expect(harness.controller.isBarredBarVisible == true)

        try await Task.sleep(for: .milliseconds(400))

        #expect(harness.controller.isBarredBarVisible == false)
        #expect(harness.divider.expandCallCount == 1)
    }

    @Test("auto-hide is suppressed while cursor is in the menu bar strip")
    func autoHideSuppressedWhileInStrip() async throws {
        let harness = makeController(
            autoHideDelay: 0.1,
            idleTickInterval: .milliseconds(20)
        )
        harness.cursorMonitor.inStrip = true
        harness.controller.toggleBarredBar()
        #expect(harness.controller.isBarredBarVisible == true)

        try await Task.sleep(for: .milliseconds(400))

        #expect(harness.controller.isBarredBarVisible == true)
        #expect(harness.divider.expandCallCount == 0)
    }

    @Test("auto-hide is suppressed while cursor is over an open menu-bar popup")
    func autoHideSuppressedWhileOverPopup() async throws {
        let harness = makeController(
            autoHideDelay: 0.1,
            idleTickInterval: .milliseconds(20)
        )
        // Cursor has left the strip (dropped down into the open dropdown) but is
        // over the popup window — the section must stay revealed.
        harness.cursorMonitor.inStrip = false
        harness.cursorMonitor.overPopup = true
        harness.controller.toggleBarredBar()
        #expect(harness.controller.isBarredBarVisible == true)

        try await Task.sleep(for: .milliseconds(400))

        #expect(harness.controller.isBarredBarVisible == true)
        #expect(harness.divider.expandCallCount == 0)
    }

    @Test("auto-hide resumes once cursor leaves the active region")
    func autoHideResumesAfterCursorLeaves() async throws {
        let harness = makeController(
            autoHideDelay: 0.1,
            idleTickInterval: .milliseconds(20)
        )
        harness.cursorMonitor.inStrip = true
        harness.controller.toggleBarredBar()

        try await Task.sleep(for: .milliseconds(250))
        #expect(harness.controller.isBarredBarVisible == true)

        harness.cursorMonitor.inStrip = false
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.controller.isBarredBarVisible == false)
    }

    @Test("toggling off cancels the pending auto-hide")
    func togglingOffCancelsAutoHide() async throws {
        let harness = makeController(
            autoHideDelay: 0.1,
            idleTickInterval: .milliseconds(20)
        )
        harness.controller.toggleBarredBar() // show
        harness.controller.toggleBarredBar() // hide immediately

        try await Task.sleep(for: .milliseconds(300))

        // Only one expand call (from the manual toggle off), not from auto-hide.
        #expect(harness.divider.expandCallCount == 1)
        #expect(harness.controller.isBarredBarVisible == false)
    }

    @Test("moveItem skips items with zero-sized frames")
    func moveItemZeroFrame() async {
        let harness = makeController()
        let zeroed = MenuBarItem(
            pid: 1,
            appName: "Z",
            bundleIdentifier: "com.test.z",
            title: "Z",
            windowID: 0,
            frame: .zero,
            itemIndex: 0,
            axElement: nil
        )
        let items = [zeroed, makeItem(id: "B", x: 140)]
        await harness.controller.moveItem(from: IndexSet(integer: 0), to: 2, in: items)
        #expect(harness.mover.performDragCallCount == 0)
    }
}
