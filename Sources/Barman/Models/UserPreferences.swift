import Foundation

struct UserPreferences: Codable {
    var itemVisibilities: [String: ItemVisibility] = [:]
    var autoHideDelay: TimeInterval = 5.0
    var showBarmanBarOnClick: Bool = true
    var launchAtLogin: Bool = false

    func visibility(for item: MenuBarItem) -> ItemVisibility {
        itemVisibilities[item.persistenceKey] ?? .alwaysShow
    }

    mutating func setVisibility(_ visibility: ItemVisibility, for item: MenuBarItem) {
        itemVisibilities[item.persistenceKey] = visibility
    }
}
