import AppKit
import ApplicationServices
import os
import ScreenCaptureKit

@MainActor
protocol MenuBarDetecting: AnyObject {
    var detectedItems: [MenuBarItem] { get }
    var hasCompletedFirstScan: Bool { get }
    func startScanning()
    func stopScanning()
    func scan() async
    func waitForFirstScan() async
}

@MainActor @Observable
final class MenuBarDetector: MenuBarDetecting {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "MenuBarDetector")
    private let accessibilityService: AccessibilityQuerying
    private(set) var detectedItems: [MenuBarItem] = []
    private(set) var hasCompletedFirstScan = false
    private var scanTask: Task<Void, Never>?
    private var firstScanContinuation: CheckedContinuation<Void, Never>?

    init(accessibilityService: AccessibilityQuerying) {
        self.accessibilityService = accessibilityService
    }

    func waitForFirstScan() async {
        if hasCompletedFirstScan { return }
        await withCheckedContinuation { continuation in
            firstScanContinuation = continuation
        }
    }

    func startScanning() {
        scanTask = Task {
            await scan()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
                await scan()
            }
        }
    }

    func stopScanning() {
        scanTask?.cancel()
        scanTask = nil
    }

    func scan() async {
        accessibilityService.checkTrust()

        let windows = await fetchStatusItemWindows()

        var items: [MenuBarItem] = if accessibilityService.isTrusted {
            detectViaAccessibility(windows: windows)
        } else {
            detectViaWindowList(windows: windows)
        }

        items = deduplicateAcrossScreens(items)

        if detectedItems.count != items.count || detectedItems.map(\.displayName) != items.map(\.displayName) {
            Self.logger.debug("Detected \(items.count) menu bar items")
            for item in items {
                Self.logger
                    .debug(
                        "  - \(item.displayName) [\(item.appName)] (wid: \(item.windowID), x: \(Int(item.frame.origin.x)))"
                    )
            }
        }

        detectedItems = items

        if !hasCompletedFirstScan {
            hasCompletedFirstScan = true
            firstScanContinuation?.resume()
            firstScanContinuation = nil
        }
    }

    // MARK: - AX-based detection enriched with window IDs

    private func detectViaAccessibility(windows: [WindowInfo]) -> [MenuBarItem] {
        let axItems = accessibilityService.enumerateAllExtrasItems()

        return axItems.compactMap { axItem -> MenuBarItem? in
            // Filter out untitled Control Centre items (spacers/separators)
            if axItem.bundleIdentifier == "com.apple.controlcenter", axItem.title == nil {
                return nil
            }

            let windowID = findWindowID(
                for: axItem,
                in: windows
            )

            return MenuBarItem(
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

    // MARK: - ScreenCaptureKit window enumeration

    private struct WindowInfo {
        let windowID: CGWindowID
        let pid: pid_t
        let frame: CGRect
    }

    /// Window layer for status bar items (menu bar extras).
    private static let statusItemWindowLayer = 25

    /// Maximum expected width for a single menu bar extra.
    /// Items wider than this are likely full menu bar backgrounds, not extras.
    private static let maxMenuBarItemWidth: Double = 300

    private func fetchStatusItemWindows() async -> [WindowInfo] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )

            return content.windows.compactMap { window -> WindowInfo? in
                guard window.windowLayer == Self.statusItemWindowLayer,
                      let app = window.owningApplication
                else { return nil }

                let frame = window.frame
                guard frame.width > 0, frame.width < Self.maxMenuBarItemWidth,
                      frame.height > 0
                else { return nil }

                return WindowInfo(
                    windowID: CGWindowID(window.windowID),
                    pid: app.processID,
                    frame: frame
                )
            }
        } catch {
            Self.logger.error("ScreenCaptureKit window enumeration failed: \(error.localizedDescription)")
            return []
        }
    }

    private func findWindowID(for axItem: AXMenuBarItemInfo, in windows: [WindowInfo]) -> CGWindowID {
        guard let axFrame = axItem.frame else { return 0 }

        var bestMatch: CGWindowID = 0
        var bestDistance: Double = .greatestFiniteMagnitude

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

    // MARK: - Window list fallback

    private func detectViaWindowList(windows: [WindowInfo]) -> [MenuBarItem] {
        var itemIndex: [Int32: Int] = [:]

        return windows.map { window in
            let app = NSRunningApplication(processIdentifier: window.pid)
            let index = itemIndex[window.pid, default: 0]
            itemIndex[window.pid] = index + 1

            return MenuBarItem(
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

        let primaryFrame = NSScreen.main?.frame ?? .zero
        let primaryFirst = items.sorted { a, b in
            let aOnPrimary = primaryFrame.contains(CGPoint(x: a.frame.midX, y: a.frame.midY))
            let bOnPrimary = primaryFrame.contains(CGPoint(x: b.frame.midX, y: b.frame.midY))
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
