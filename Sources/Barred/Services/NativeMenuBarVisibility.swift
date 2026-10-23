import AppKit
import os

@MainActor
protocol MenuBarVisibilityHolding: AnyObject, Sendable {
    func invalidate()
}

@MainActor
protocol MenuBarVisibilityActivating {
    func activate(visibleApps: Set<String>) async -> (any MenuBarVisibilityHolding)?
}

@MainActor
struct NativeVisibilityBridge: MenuBarVisibilityActivating {
    func activate(visibleApps: Set<String>) async -> (any MenuBarVisibilityHolding)? {
        await withCheckedContinuation { continuation in
            BarredActivateVisibility(visibleApps.sorted()) { handle, error in
                MainActor.assumeIsolated {
                    if let error {
                        Logger(subsystem: "com.mcclowes.barred", category: "Visibility")
                            .error("Menu bar hiding failed: \(error.localizedDescription)")
                    }
                    continuation.resume(returning: handle.map { NativeVisibilityHandle(raw: $0) })
                }
            }
        }
    }
}

@MainActor
private final class NativeVisibilityHandle: MenuBarVisibilityHolding {
    private var raw: Any?

    init(raw: Any) {
        self.raw = raw
    }

    func invalidate() {
        guard let raw else { return }
        self.raw = nil
        BarredInvalidateVisibility(raw)
    }
}

@MainActor @Observable
final class NativeMenuBarVisibility {
    private let accessibility: any AccessibilityQuerying
    private let bridge: any MenuBarVisibilityActivating
    private let runningBundles: () -> Set<String>
    private let ownBundleIdentifier: String
    private let isApplicationRegistered: () -> Bool
    private var handle: (any MenuBarVisibilityHolding)?
    private var generation = 0
    private(set) var hiddenBundleIdentifiers = Set<String>()
    private(set) var unavailableReason: String?

    init(
        accessibility: any AccessibilityQuerying,
        bridge: any MenuBarVisibilityActivating = NativeVisibilityBridge(),
        runningBundles: @escaping () -> Set<String> = {
            Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        },
        ownBundleIdentifier: String = Bundle.main.bundleIdentifier ?? "com.mcclowes.barred",
        isApplicationRegistered: @escaping () -> Bool = {
            guard let bundle = Bundle.main.bundleIdentifier,
                  let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
            else { return false }
            return registered.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        }
    ) {
        self.accessibility = accessibility
        self.bridge = bridge
        self.runningBundles = runningBundles
        self.ownBundleIdentifier = ownBundleIdentifier
        self.isApplicationRegistered = isApplicationRegistered
    }

    func hide(between first: CGRect, and second: CGRect) async -> Bool {
        show()
        let request = generation
        accessibility.checkTrust()
        guard accessibility.isTrusted else {
            unavailableReason = "Allow Barred in Accessibility to hide menu bar items."
            return false
        }
        guard isApplicationRegistered() else {
            unavailableReason = "Run this build from Applications so macOS can keep Barred’s controls visible."
            return false
        }
        guard first.width > 0, second.width > 0,
              first.intersects(CGRect(x: first.minX, y: second.minY, width: first.width, height: second.height))
        else {
            unavailableReason = "Barred can’t read both section markers yet. Try again."
            return false
        }

        let hidden = Self.hiddenBundles(
            in: accessibility.enumerateAllExtrasItems(),
            between: first, and: second, ownBundleIdentifier: ownBundleIdentifier
        )
        guard !hidden.isEmpty else { return true }
        let visible = runningBundles().subtracting(hidden).union([ownBundleIdentifier])
        let activated = await bridge.activate(visibleApps: visible)
        guard generation == request, !Task.isCancelled else {
            activated?.invalidate()
            return false
        }
        handle = activated
        hiddenBundleIdentifiers = activated == nil ? [] : hidden
        unavailableReason = activated == nil ? "macOS couldn’t hide the section. Its icons have been left visible." :
            nil
        return activated != nil
    }

    func show() {
        generation += 1
        handle?.invalidate()
        handle = nil
        hiddenBundleIdentifiers = []
        unavailableReason = nil
    }

    static func hiddenBundles(
        in items: [AXMenuBarItemInfo],
        between first: CGRect,
        and second: CGRect,
        ownBundleIdentifier: String
    ) -> Set<String> {
        let left = first.midX < second.midX ? first : second
        let right = first.midX < second.midX ? second : first
        var inside = Set<String>()
        var outside = Set<String>()
        for item in items {
            guard let bundle = item.bundleIdentifier else { continue }
            guard let frame = item.frame, frame.width > 0, frame.height > 0 else {
                outside.insert(bundle)
                continue
            }
            guard frame.maxY > left.minY, frame.minY < left.maxY else { continue }
            let inSection = frame.midX > left.maxX && frame.midX < right.minX
            if inSection {
                inside.insert(bundle)
            } else {
                outside.insert(bundle)
            }
        }
        return inside.subtracting(outside).subtracting([
            ownBundleIdentifier, "com.apple.controlcenter", "com.apple.systemuiserver"
        ])
    }
}
