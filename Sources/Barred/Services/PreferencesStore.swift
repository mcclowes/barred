import Foundation

@Observable
final class PreferencesStore {
    private static let key = "com.barred.preferences"
    var preferences: UserPreferences

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = UserPreferences()
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
