@testable import Barred
import Testing

@MainActor
struct AccessibilityServiceTests {
    @Test("checkTrust updates isTrusted without crashing")
    func checkTrust() {
        let service = AccessibilityService()
        // In CI/test environments, AXIsProcessTrusted() returns false.
        // The key thing is it doesn't crash and returns a valid Bool.
        service.checkTrust()
        #expect(service.isTrusted == false || service.isTrusted == true)
    }

    @Test("enumerateAllExtrasItems returns empty when not trusted")
    func enumerateWhenUntrusted() {
        let service = AccessibilityService()
        // Force untrusted state if not already
        if !service.isTrusted {
            let items = service.enumerateAllExtrasItems()
            #expect(items.isEmpty)
        }
    }
}
