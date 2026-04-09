import Foundation

@MainActor
protocol PreferencesStoring: AnyObject {
    var preferences: UserPreferences { get set }
}

@MainActor @Observable
final class PreferencesStore: PreferencesStoring {
    private static let key = "com.barred.preferences"

    var preferences: UserPreferences {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(UserPreferences.self, from: data)
        {
            preferences = decoded
        } else {
            preferences = UserPreferences()
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(preferences) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
