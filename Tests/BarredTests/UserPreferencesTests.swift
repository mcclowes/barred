import Foundation
import Testing
@testable import Barred

@Suite("UserPreferences")
struct UserPreferencesTests {
    @Test("defaults are sensible")
    func defaults() {
        let prefs = UserPreferences()
        #expect(prefs.autoHideDelay == 5.0)
        #expect(prefs.showBarredBarOnClick == true)
        #expect(prefs.launchAtLogin == false)
    }

    @Test("round-trips through JSON")
    func codableRoundTrip() throws {
        var prefs = UserPreferences()
        prefs.autoHideDelay = 10.0
        prefs.showBarredBarOnClick = false
        prefs.launchAtLogin = true

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)

        #expect(decoded.autoHideDelay == 10.0)
        #expect(decoded.showBarredBarOnClick == false)
        #expect(decoded.launchAtLogin == true)
    }

    @Test("decodes from partial JSON with defaults")
    func decodesPartialJSON() throws {
        let json = Data("{}".utf8)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: json)

        #expect(decoded.autoHideDelay == 5.0)
        #expect(decoded.showBarredBarOnClick == true)
        #expect(decoded.launchAtLogin == false)
    }
}
