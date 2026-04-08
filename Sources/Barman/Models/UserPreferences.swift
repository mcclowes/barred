import Foundation

struct UserPreferences: Codable {
    var autoHideDelay: TimeInterval = 5.0
    var showBarmanBarOnClick: Bool = true
    var launchAtLogin: Bool = false

    init(
        autoHideDelay: TimeInterval = 5.0,
        showBarmanBarOnClick: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.autoHideDelay = autoHideDelay
        self.showBarmanBarOnClick = showBarmanBarOnClick
        self.launchAtLogin = launchAtLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoHideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .autoHideDelay) ?? 5.0
        showBarmanBarOnClick = try container.decodeIfPresent(Bool.self, forKey: .showBarmanBarOnClick) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}
