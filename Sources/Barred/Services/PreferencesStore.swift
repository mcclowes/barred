import Foundation
import os

@MainActor
protocol PreferencesStoring: AnyObject {
    var preferences: UserPreferences { get set }
}

@MainActor @Observable
final class PreferencesStore: PreferencesStoring {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "PreferencesStore")
    nonisolated static let defaultsKey = "com.mcclowes.barred.preferences"

    private let defaults: UserDefaults
    private let key: String

    var preferences: UserPreferences {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard, key: String = PreferencesStore.defaultsKey) {
        self.defaults = defaults
        self.key = key

        guard let data = defaults.data(forKey: key) else {
            preferences = UserPreferences()
            return
        }

        do {
            preferences = try JSONDecoder().decode(UserPreferences.self, from: data)
        } catch {
            Self.logger
                .error(
                    "Failed to decode preferences: \(error.localizedDescription, privacy: .public) — falling back to defaults"
                )
            defaults.set(data, forKey: "\(key).corrupted")
            preferences = UserPreferences()
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: key)
        } catch {
            Self.logger.error("Failed to encode preferences: \(error.localizedDescription, privacy: .public)")
        }
    }
}
