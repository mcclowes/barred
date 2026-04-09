@testable import Barred
import Foundation
import Testing

@MainActor
struct PreferencesStoreTests {
    @Test("initialises with defaults when no saved data exists")
    func defaultInit() {
        let key = "com.barred.preferences"
        let saved = UserDefaults.standard.data(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)

        let store = PreferencesStore()
        #expect(store.preferences.autoHideDelay == 5.0)
        #expect(store.preferences.showBarredBarOnClick == true)
        #expect(store.preferences.launchAtLogin == false)

        // Restore
        if let saved {
            UserDefaults.standard.set(saved, forKey: key)
        }
    }

    @Test("mutation auto-persists to UserDefaults")
    func autoSave() {
        let key = "com.barred.preferences"
        let saved = UserDefaults.standard.data(forKey: key)

        let store = PreferencesStore()
        store.preferences.autoHideDelay = 12.0

        // Read raw data back from UserDefaults
        let data = UserDefaults.standard.data(forKey: key)
        #expect(data != nil)

        if let data {
            let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data)
            #expect(decoded?.autoHideDelay == 12.0)
        }

        // Restore
        if let saved {
            UserDefaults.standard.set(saved, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
