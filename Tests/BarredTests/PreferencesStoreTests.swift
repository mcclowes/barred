@testable import Barred
import Foundation
import Testing

@MainActor
struct PreferencesStoreTests {
    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test("initialises with defaults when no saved data exists")
    func defaultInit() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults, key: "prefs")
        #expect(store.preferences.autoHideDelay == 5.0)
        #expect(store.preferences.showBarredBarOnClick == true)
        #expect(store.preferences.launchAtLogin == false)
    }

    @Test("mutation auto-persists to UserDefaults")
    func autoSave() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PreferencesStore(defaults: defaults, key: "prefs")
        store.preferences.autoHideDelay = 12.0

        let data = defaults.data(forKey: "prefs")
        #expect(data != nil)

        let decoded = try? JSONDecoder().decode(UserPreferences.self, from: #require(data))
        #expect(decoded?.autoHideDelay == 12.0)
    }

    @Test("corrupted data falls back to defaults and preserves the bad blob")
    func corruptedDataFallback() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let badData = Data("not json".utf8)
        defaults.set(badData, forKey: "prefs")

        let store = PreferencesStore(defaults: defaults, key: "prefs")
        #expect(store.preferences.autoHideDelay == 5.0)
        #expect(defaults.data(forKey: "prefs.corrupted") == badData)
    }

    @Test("reloads previously saved preferences")
    func reloadAfterSave() {
        let (defaults, suite) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = PreferencesStore(defaults: defaults, key: "prefs")
        first.preferences.autoHideDelay = 9.0
        first.preferences.showBarredBarOnClick = false

        let second = PreferencesStore(defaults: defaults, key: "prefs")
        #expect(second.preferences.autoHideDelay == 9.0)
        #expect(second.preferences.showBarredBarOnClick == false)
    }
}
