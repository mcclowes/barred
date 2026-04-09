import Foundation

struct UserPreferences: Codable {
    var autoHideDelay: TimeInterval = 5.0
    var showBarredBarOnClick: Bool = true
    var launchAtLogin: Bool = false

    init(
        autoHideDelay: TimeInterval = 5.0,
        showBarredBarOnClick: Bool = true,
        launchAtLogin: Bool = false
    ) {
        self.autoHideDelay = autoHideDelay
        self.showBarredBarOnClick = showBarredBarOnClick
        self.launchAtLogin = launchAtLogin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoHideDelay = try min(
            60.0,
            max(1.0, container.decodeIfPresent(TimeInterval.self, forKey: .autoHideDelay) ?? 5.0)
        )
        showBarredBarOnClick = try container.decodeIfPresent(Bool.self, forKey: .showBarredBarOnClick) ?? true
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}
