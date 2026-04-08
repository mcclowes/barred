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

        items = deduplicateAcrossScreens(items)

        if detectedItems.count != items.count || detectedItems.map(\.displayName) != items.map(\.displayName) {
            print("[Barred] Detected \(items.count) menu bar items:")
            for item in items {
                print("  - \(item.displayName) [\(item.appName)] (wid: \(item.windowID), x: \(Int(item.frame.origin.x)))")
            }
        }

        detectedItems = items
    }

    // MARK: - AX-based detection enriched with window IDs

    private func detectViaAccessibility() -> [MenuBarItem] {
        let axItems = accessibilityService.enumerateAllExtrasItems()
        let windowMap = menuBarWindowMap()

        return axItems.compactMap { axItem -> MenuBarItem? in
            // Filter out untitled Control Centre items (spacers/separators)
            if axItem.bundleIdentifier == "com.apple.controlcenter" && axItem.title == nil {
                return nil
            }

            // Match AX item to a CGWindowList window by PID + position overlap
            let windowID = findWindowID(
                for: axItem,
                in: windowMap
            )

            return MenuBarItem(
                id: "\(axItem.pid)-\(axItem.indexInApp)",
                pid: axItem.pid,
                appName: axItem.appName,
                bundleIdentifier: axItem.bundleIdentifier,
                title: axItem.title,
                windowID: windowID,
                frame: axItem.frame ?? .zero,
                itemIndex: axItem.indexInApp,
                axElement: axItem.element
            )
        }
        .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    // MARK: - CGWindowList for window IDs

    private struct WindowInfo {
        let windowID: CGWindowID
        let pid: pid_t
        let frame: CGRect
    }

    private func menuBarWindowMap() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { info -> WindowInfo? in
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 25,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let ownerPID = info[kCGWindowOwnerPID as String] as? Int32
            else { return nil }

            let x = (boundsDict["X"] as? NSNumber)?.doubleValue ?? 0
            let y = (boundsDict["Y"] as? NSNumber)?.doubleValue ?? 0
            let width = (boundsDict["Width"] as? NSNumber)?.doubleValue ?? 0
            let height = (boundsDict["Height"] as? NSNumber)?.doubleValue ?? 0
            let frame = CGRect(x: x, y: y, width: width, height: height)

            guard width > 0, width < 200, height > 0 else { return nil }

            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0

            return WindowInfo(windowID: windowID, pid: ownerPID, frame: frame)
        }
    }

    private func findWindowID(for axItem: AXMenuBarItemInfo, in windows: [WindowInfo]) -> CGWindowID {
        guard let axFrame = axItem.frame else { return 0 }

        // Find the window with matching PID and closest position
        var bestMatch: CGWindowID = 0
        var bestDistance: CGFloat = .greatestFiniteMagnitude

        for window in windows where window.pid == axItem.pid {
            let dx = abs(window.frame.origin.x - axFrame.origin.x)
            let dy = abs(window.frame.origin.y - axFrame.origin.y)
            let distance = dx + dy

            if distance < bestDistance {
                bestDistance = distance
                bestMatch = window.windowID
            }
        }

        return bestMatch
    }

    // MARK: - CGWindowList fallback

    private func detectViaWindowList() -> [MenuBarItem] {
        let windows = menuBarWindowMap()
        var itemIndex: [Int32: Int] = [:]

        return windows.map { window in
            let app = NSRunningApplication(processIdentifier: window.pid)
            let index = itemIndex[window.pid, default: 0]
            itemIndex[window.pid] = index + 1

            return MenuBarItem(
                id: "\(window.pid)-\(window.windowID)",
                pid: window.pid,
                appName: app?.localizedName ?? "Unknown",
                bundleIdentifier: app?.bundleIdentifier,
                title: nil,
                windowID: window.windowID,
                frame: window.frame,
                itemIndex: index,
                axElement: nil
            )
        }
        .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    // MARK: - Deduplication

    private func deduplicateAcrossScreens(_ items: [MenuBarItem]) -> [MenuBarItem] {
        var seen = Set<String>()
        var result: [MenuBarItem] = []

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
