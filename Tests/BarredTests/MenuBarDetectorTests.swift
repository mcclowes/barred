@testable import Barred
import Testing

@MainActor
private final class StubAccessibilityService: AccessibilityQuerying {
    var isTrusted = false
    func checkTrust() {}
    func requestTrust() {}
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo] {
        []
    }
}

@MainActor
struct MenuBarDetectorTests {
    @Test("starts with empty detected items")
    func initialState() {
        let detector = MenuBarDetector(accessibilityService: StubAccessibilityService())
        #expect(detector.detectedItems.isEmpty)
        #expect(detector.hasCompletedFirstScan == false)
    }

    @Test("scan completes first scan flag")
    func scanCompletesFirstScan() async {
        let detector = MenuBarDetector(accessibilityService: StubAccessibilityService())
        await detector.scan()
        #expect(detector.hasCompletedFirstScan == true)
    }

    @Test("scan with untrusted service uses window list fallback")
    func scanUntrusted() async {
        let service = StubAccessibilityService()
        service.isTrusted = false
        let detector = MenuBarDetector(accessibilityService: service)
        await detector.scan()
        // Should not crash; items come from ScreenCaptureKit which may be empty in test
        #expect(detector.hasCompletedFirstScan == true)
    }

    @Test("stopScanning cancels scan task")
    func stopScanning() async {
        let detector = MenuBarDetector(accessibilityService: StubAccessibilityService())
        detector.startScanning()
        // Give the initial scan a moment to complete
        try? await Task.sleep(for: .milliseconds(100))
        detector.stopScanning()
        // Should not crash or leave dangling tasks
    }

    @Test("waitForFirstScan returns immediately if already scanned")
    func waitAfterScan() async {
        let detector = MenuBarDetector(accessibilityService: StubAccessibilityService())
        await detector.scan()
        // Should return immediately without hanging
        await detector.waitForFirstScan()
        #expect(detector.hasCompletedFirstScan == true)
    }
}
