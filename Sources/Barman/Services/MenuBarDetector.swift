import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor @Observable
final class MenuBarDetector {
    private let accessibilityService: AccessibilityService
    private(set) var detectedItems: [MenuBarItem] = []
    private var timer: Timer?

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

    func startScanning() {
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
    }

    func stopScanning() {
        timer?.invalidate()
        timer = nil
    }

    func scan() {
        var items: [MenuBarItem]

        if accessibilityService.isTrusted {
            items = detectViaAccessibility()
        } else {
            items = detectViaWindowList()
        }

        // Deduplicate across screens — same app+title appearing on multiple monitors
        items = deduplicateAcrossScreens(items)

        if detectedItems.count != items.count || detectedItems.map(\.displayName) != items.map(\.displayName) {
            print("[Barman] Detected \(items.count) menu bar items:")
            for item in items {
                print("  - \(item.displayName) [\(item.appName)] (x: \(Int(item.frame.origin.x)))")
            }
        }

        detectedItems = items
    }

    // MARK: - AX-based detection (primary, more accurate)

    private func detectViaAccessibility() -> [MenuBarItem] {
        let axItems = accessibilityService.enumerateAllExtrasItems()

        return axItems.compactMap { axItem -> MenuBarItem? in
            // Filter out untitled Control Centre items — these are spacers/separators/background
            if axItem.bundleIdentifier == "com.apple.controlcenter" && axItem.title == nil {
                return nil
            }

            return MenuBarItem(
                id: "\(axItem.pid)-\(axItem.indexInApp)",
                pid: axItem.pid,
                appName: axItem.appName,
                bundleIdentifier: axItem.bundleIdentifier,
                title: axItem.title,
                windowID: 0,
                frame: axItem.frame ?? .zero,
                itemIndex: axItem.indexInApp
            )
        }
        .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    // MARK: - CGWindowList fallback (when AX not available)

    private func detectViaWindowList() -> [MenuBarItem] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        var itemIndex: [Int32: Int] = [:]

        return windowList.compactMap { info -> MenuBarItem? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 25,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32,
                  let ownerName = info[kCGWindowOwnerName as String] as? String
            else { return nil }

            let x = (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0
            let width = (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0
            let frame = CGRect(x: x, y: y, width: width, height: height)

            guard width > 0, width < 200, height > 0 else { return nil }

            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            let app = NSRunningApplication(processIdentifier: ownerPID)
            let bundleID = app?.bundleIdentifier
            let windowName = info[kCGWindowName as String] as? String

            let index = itemIndex[ownerPID, default: 0]
            itemIndex[ownerPID] = index + 1

            return MenuBarItem(
                id: "\(ownerPID)-\(windowID)",
                pid: ownerPID,
                appName: ownerName,
                bundleIdentifier: bundleID,
                title: windowName,
                windowID: windowID,
                frame: frame,
                itemIndex: index
            )
        }
        .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    // MARK: - Deduplication

    /// Menu bar items appear on every screen. Keep only one instance of each
    /// unique item (by app + title), preferring the one on the primary screen.
    private func deduplicateAcrossScreens(_ items: [MenuBarItem]) -> [MenuBarItem] {
        var seen = Set<String>()
        var result: [MenuBarItem] = []

        // Sort so primary screen items (x >= 0 on typical setups) come first
        let primaryFirst = items.sorted { a, b in
            let aOnPrimary = a.frame.origin.x >= 0
            let bOnPrimary = b.frame.origin.x >= 0
            if aOnPrimary != bOnPrimary { return aOnPrimary }
            return a.frame.origin.x < b.frame.origin.x
        }

        for item in primaryFirst {
            let key = item.persistenceKey
            if seen.contains(key) { continue }
            seen.insert(key)
            result.append(item)
        }

        return result.sorted { $0.frame.origin.x < $1.frame.origin.x }
    }
}
