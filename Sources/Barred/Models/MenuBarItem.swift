import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

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

    var isHidden: Bool {
        frame.origin.x < 0
    }

    var displayName: String {
        displayName(showIndex: true)
    }

    func displayName(showIndex: Bool) -> String {
        if let title, !title.isEmpty {
            return title
        }
        return showIndex ? "\(appName) #\(itemIndex + 1)" : appName
    }

    var subtitle: String? {
        if let title, !title.isEmpty {
            return appName
        }
        return nil
    }

    var appIcon: NSImage? {
        if let bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier ?? "").first?.icon
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
