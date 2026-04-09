import AppKit
import ApplicationServices

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
    let appIcon: NSImage?

    init(
        pid: pid_t,
        appName: String,
        bundleIdentifier: String?,
        title: String?,
        windowID: CGWindowID,
        frame: CGRect,
        itemIndex: Int,
        axElement: AXUIElement?
    ) {
        self.pid = pid
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.windowID = windowID
        self.frame = frame
        self.itemIndex = itemIndex
        self.axElement = axElement

        // Stable ID: prefer bundle identifier over PID (PIDs change on every app restart)
        let bundle = bundleIdentifier ?? "pid-\(pid)"
        let itemTitle = title ?? "item-\(itemIndex)"
        self.id = "\(bundle):\(itemTitle)"

        // Cache icon at creation time to avoid filesystem I/O on every SwiftUI render
        self.appIcon = Self.loadIcon(for: bundleIdentifier)
    }

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

    var persistenceKey: String {
        id
    }

    private static func loadIcon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier else { return nil }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first?.icon
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
