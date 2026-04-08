import Foundation
import CoreGraphics

struct MenuBarItem: Identifiable, Hashable {
    let id: String
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String?
    let title: String?
    let windowID: CGWindowID
    var frame: CGRect
    let itemIndex: Int

    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        return "\(appName) #\(itemIndex + 1)"
    }

    var subtitle: String? {
        if title != nil, !title!.isEmpty {
            return appName
        }
        return nil
    }

    var persistenceKey: String {
        let bundle = bundleIdentifier ?? "pid-\(pid)"
        let itemTitle = title ?? "item-\(itemIndex)"
        return "\(bundle):\(itemTitle)"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id
    }
}
