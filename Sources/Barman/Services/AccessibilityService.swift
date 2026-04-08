import ApplicationServices
import AppKit
import Foundation

@MainActor @Observable
final class AccessibilityService {
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
    /// Queries each running app for its AXExtrasMenuBar children.
    func enumerateAllExtrasItems() -> [AXMenuBarItemInfo] {
        guard isTrusted else { return [] }

        var results: [AXMenuBarItemInfo] = []

        // Query ALL running applications — including system agents
        let apps = NSWorkspace.shared.runningApplications

        for app in apps {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)

            // Try AXExtrasMenuBar — this is the right-side menu bar (status items)
            guard let extrasMenuBar: AXUIElement = axApp.attribute("AXExtrasMenuBar") else {
                continue
            }

            let children = extrasMenuBar.children()
            for (index, child) in children.enumerated() {
                let title = child.title()
                let desc = child.description_()
                let identifier = child.identifier()
                let frame = child.frame()

                // Build the best display name we can
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
