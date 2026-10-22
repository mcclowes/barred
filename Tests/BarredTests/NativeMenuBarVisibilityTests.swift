import AppKit
import ApplicationServices
@testable import Barred
import Testing

@MainActor
private final class VisibilityAccessibility: AccessibilityQuerying {
    var isTrusted = true
    var items: [AXMenuBarItemInfo] = []
    func checkTrust() {}
    func requestTrust() {}
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo] {
        items
    }
}

@MainActor
private final class VisibilityHandle: MenuBarVisibilityHolding {
    var invalidated = false
    func invalidate() {
        invalidated = true
    }
}

@MainActor
private final class VisibilityBridge: MenuBarVisibilityActivating {
    var visibleApps = Set<String>()
    var result: VisibilityHandle? = VisibilityHandle()
    var suspend = false
    private let started = AsyncStream<Void>.makeStream()
    private var pending: CheckedContinuation<(any MenuBarVisibilityHolding)?, Never>?

    func activate(visibleApps: Set<String>) async -> (any MenuBarVisibilityHolding)? {
        self.visibleApps = visibleApps
        if suspend {
            return await withCheckedContinuation {
                pending = $0
                started.continuation.yield(())
            }
        }
        started.continuation.yield(())
        return result
    }

    func waitForActivation() async {
        for await _ in started.stream {
            return
        }
    }

    func complete() {
        pending?.resume(returning: result)
        pending = nil
    }
}

@MainActor
struct NativeMenuBarVisibilityTests {
    private struct Harness {
        let visibility: NativeMenuBarVisibility
        let accessibility: VisibilityAccessibility
        let bridge: VisibilityBridge
    }

    @Test("only apps between both markers are hidden", .bug("https://github.com/mcclowes/barred/issues/46"))
    func boundedSection() {
        let items = [
            makeItem("left", x: 40),
            makeItem("inside", x: 140),
            makeItem("right", x: 240),
            makeItem("other-display", x: 140, y: 900),
            makeItem("inside", x: 140, y: 900),
            makeItem("com.mcclowes.barred", x: 160)
        ]
        #expect(NativeMenuBarVisibility.hiddenBundles(
            in: items,
            between: CGRect(x: 100, y: 0, width: 20, height: 24),
            and: CGRect(x: 200, y: 0, width: 20, height: 24),
            ownBundleIdentifier: "com.mcclowes.barred"
        ) == ["inside"])
    }

    @Test("native hiding preserves apps on either side and the Barred control")
    func nativeAllowList() async {
        let harness = makeVisibility()
        let visibility = harness.visibility
        let accessibility = harness.accessibility
        let bridge = harness.bridge
        accessibility.items = [makeItem("inside", x: 140), makeItem("left", x: 40), makeItem("right", x: 240)]
        let hidden = await visibility.hide(between: start, and: end)
        #expect(hidden)
        #expect(visibility.hiddenBundleIdentifiers == ["inside"])
        #expect(bridge.visibleApps == ["left", "right", "com.mcclowes.barred"])
        visibility.show()
        #expect(visibility.hiddenBundleIdentifiers.isEmpty)
        #expect(bridge.result?.invalidated == true)
    }

    @Test("missing Accessibility access does not hide any apps")
    func missingPermission() async {
        let harness = makeVisibility()
        let visibility = harness.visibility
        let accessibility = harness.accessibility
        let bridge = harness.bridge
        accessibility.isTrusted = false
        accessibility.items = [makeItem("inside", x: 140)]
        #expect(await visibility.hide(between: start, and: end) == false)
        #expect(bridge.visibleApps.isEmpty)
    }

    @Test(
        "the first app can be added after hiding an empty section",
        .bug("https://github.com/mcclowes/barred/issues/46")
    )
    func firstAppInEmptySection() async {
        let harness = makeVisibility()
        #expect(await harness.visibility.hide(between: start, and: end))
        #expect(harness.bridge.visibleApps.isEmpty)
        harness.visibility.show()
        harness.accessibility.items = [makeItem("inside", x: 140)]
        #expect(await harness.visibility.hide(between: start, and: end))
        #expect(harness.visibility.hiddenBundleIdentifiers == ["inside"])
        harness.visibility.show()
    }

    @Test("native activation failure leaves the section visible")
    func activationFailure() async {
        let harness = makeVisibility()
        let visibility = harness.visibility
        let accessibility = harness.accessibility
        let bridge = harness.bridge
        accessibility.items = [makeItem("inside", x: 140)]
        bridge.result = nil
        #expect(await visibility.hide(between: start, and: end) == false)
    }

    @Test("show invalidates a late native activation")
    func staleActivation() async {
        let harness = makeVisibility()
        let visibility = harness.visibility
        let accessibility = harness.accessibility
        let bridge = harness.bridge
        accessibility.items = [makeItem("inside", x: 140)]
        bridge.suspend = true
        let hiding = Task { await visibility.hide(between: start, and: end) }
        await bridge.waitForActivation()
        visibility.show()
        bridge.complete()
        #expect(await hiding.value == false)
        #expect(bridge.result?.invalidated == true)
    }

    @Test("canceling a hide releases a late native activation")
    func canceledActivation() async {
        let harness = makeVisibility()
        harness.accessibility.items = [makeItem("inside", x: 140)]
        harness.bridge.suspend = true
        let hiding = Task { await harness.visibility.hide(between: start, and: end) }
        await harness.bridge.waitForActivation()
        hiding.cancel()
        harness.bridge.complete()
        #expect(await hiding.value == false)
        #expect(harness.bridge.result?.invalidated == true)
        #expect(harness.visibility.hiddenBundleIdentifiers.isEmpty)
    }

    private var start: CGRect {
        CGRect(x: 100, y: 0, width: 20, height: 24)
    }

    private var end: CGRect {
        CGRect(x: 200, y: 0, width: 20, height: 24)
    }

    private func makeVisibility(registered: Bool = true) -> Harness {
        let accessibility = VisibilityAccessibility()
        let bridge = VisibilityBridge()
        return Harness(visibility: NativeMenuBarVisibility(
            accessibility: accessibility,
            bridge: bridge,
            runningBundles: { ["left", "inside", "right", "com.mcclowes.barred"] },
            ownBundleIdentifier: "com.mcclowes.barred",
            isApplicationRegistered: { registered }
        ), accessibility: accessibility, bridge: bridge)
    }

    @Test("an app with an icon outside the section stays visible")
    func visibleIconWins() {
        #expect(NativeMenuBarVisibility.hiddenBundles(
            in: [makeItem("shared", x: 140), makeItem("shared", x: 240)],
            between: CGRect(x: 100, y: 0, width: 20, height: 24),
            and: CGRect(x: 200, y: 0, width: 20, height: 24),
            ownBundleIdentifier: "com.mcclowes.barred"
        ).isEmpty)
    }

    @Test("a mismatched registered app leaves all icons visible")
    func mismatchedApplication() async {
        let harness = makeVisibility(registered: false)
        harness.accessibility.items = [makeItem("inside", x: 140)]
        #expect(await harness.visibility.hide(between: start, and: end) == false)
        #expect(harness.bridge.visibleApps.isEmpty)
        #expect(harness.visibility.unavailableReason != nil)
    }

    @Test("empty and reversed boundaries are safe", arguments: [false, true])
    func boundaryOrder(reversed: Bool) {
        let first = CGRect(x: reversed ? 200 : 100, y: 0, width: 20, height: 24)
        let second = CGRect(x: reversed ? 100 : 200, y: 0, width: 20, height: 24)
        #expect(NativeMenuBarVisibility.hiddenBundles(
            in: [], between: first, and: second, ownBundleIdentifier: "com.mcclowes.barred"
        ).isEmpty)
        #expect(NativeMenuBarVisibility.hiddenBundles(
            in: [makeItem("first", x: 140)],
            between: first, and: second, ownBundleIdentifier: "com.mcclowes.barred"
        ) == ["first"])
    }

    private func makeItem(_ bundle: String, x: CGFloat, y: CGFloat = 0) -> AXMenuBarItemInfo {
        AXMenuBarItemInfo(
            pid: 1, appName: bundle, bundleIdentifier: bundle, title: bundle,
            frame: CGRect(x: x, y: y, width: 20, height: 24), indexInApp: 0,
            element: AXUIElementCreateSystemWide()
        )
    }
}
