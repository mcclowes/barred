@testable import Barred
import Foundation
import Testing

struct UserPreferencesClampingTests {
    @Test("autoHideDelay is clamped to minimum of 1.0 on decode")
    func clampMin() throws {
        let json = Data(#"{"autoHideDelay": -5}"#.utf8)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: json)
        #expect(decoded.autoHideDelay == 1.0)
    }

    @Test("autoHideDelay is clamped to maximum of 15.0 on decode")
    func clampMax() throws {
        let json = Data(#"{"autoHideDelay": 999}"#.utf8)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: json)
        #expect(decoded.autoHideDelay == 15.0)
    }

    @Test("autoHideDelay at boundary values is accepted")
    func clampBoundary() throws {
        let jsonMin = Data(#"{"autoHideDelay": 1.0}"#.utf8)
        let decodedMin = try JSONDecoder().decode(UserPreferences.self, from: jsonMin)
        #expect(decodedMin.autoHideDelay == 1.0)

        let jsonMax = Data(#"{"autoHideDelay": 15.0}"#.utf8)
        let decodedMax = try JSONDecoder().decode(UserPreferences.self, from: jsonMax)
        #expect(decodedMax.autoHideDelay == 15.0)
    }
}
