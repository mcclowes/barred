import AppKit
import ApplicationServices
import os

@MainActor
protocol AccessibilityQuerying: AnyObject {
    var isTrusted: Bool { get }
    func checkTrust()
    func requestTrust()
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo]
}

@MainActor @Observable
final class AccessibilityService: AccessibilityQuerying {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "AccessibilityService")
    private(set) var isTrusted = false
    init() {
        checkTrust()
    }

    func checkTrust() {
        isTrusted = AXIsProcessTrusted()
    }

    func requestTrust() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Enumerate all menu bar extras (right-side status items) via AX.
    /// Queries running apps that could have menu extras (regular and accessory apps).
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo] {
        guard isTrusted else { return [] }

        var results: [AXMenuBarItemInfo] = []

        // Only query apps with regular or accessory activation policies —
        // prohibited apps (background agents, XPC, daemons) never have menu extras.
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular || $0.activationPolicy == .accessory
        }

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)

            guard let extrasMenuBar: AXUIElement = axApp.attribute("AXExtrasMenuBar") else {
                continue
            }

            let children = extrasMenuBar.children()
            for (index, child) in children.enumerated() {
                let title = child.title()
                let desc = child.description_()
                let identifier = child.identifier()
                let frame = child.frame()

                let displayName = title ?? desc ?? identifier

                results.append(AXMenuBarItemInfo(
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? app.bundleIdentifier ?? "Unknown",
                    bundleIdentifier: app.bundleIdentifier,
                    title: displayName,
                    frame: frame,
                    indexInApp: index,
                    element: child
                ))
            }
        }

        return results
    }
}

struct AXMenuBarItemInfo {
    let pid: pid_t
    let appName: String
    let bundleIdentifier: String?
    let title: String?
    let frame: CGRect?
    let indexInApp: Int
    let element: AXUIElement
}
