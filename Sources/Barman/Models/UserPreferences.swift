import Foundation

struct UserPreferences: Codable {
    var autoHideDelay: TimeInterval = 5.0
    var showBarmanBarOnClick: Bool = true
    var launchAtLogin: Bool = false
}
