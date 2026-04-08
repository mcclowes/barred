import ApplicationServices
import Foundation
import CoreGraphics

struct MenuBarItem: Identifiable {
    let id: String
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String?
    let title: String?
    let windowID: CGWindowID
    var frame: CGRect
    let itemIndex: Int
    let axElement: AXUIElement?

    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        return "\(appName) #\(itemIndex + 1)"
    }

    var subtitle: String? {
        if let title, !title.isEmpty {
            return appName
        }
        return nil
    }

    var persistenceKey: String {
        let bundle = bundleIdentifier ?? "pid-\(pid)"
        let itemTitle = title ?? "item-\(itemIndex)"
        return "\(bundle):\(itemTitle)"
    }
}

extension MenuBarItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MenuBarItem, rhs: MenuBarItem) -> Bool {
        lhs.id == rhs.id
    }
}
