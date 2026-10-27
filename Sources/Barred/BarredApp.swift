import AppKit
import os
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let logger = Logger(subsystem: "com.mcclowes.barred", category: "AppDelegate")
    nonisolated static let hasPresentedOnboardingKey = "com.mcclowes.barred.hasPresentedOnboarding"
    let controller: MenuBarController
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    override init() {
        self.controller = MenuBarController()
        super.init()
    }

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "BarredControl"
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "Barred"
            )
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
            button.toolTip = "Barred: Option-click to open the menu"
        }

        popover = Self.makeMenuPopover(controller: controller)

        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verify-menu-bar-layout") {
                Task { await runSectionDiagnostic() }
                return
            }
        #endif
        controller.start()

        if Self.shouldPresentOnboarding() {
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    static func makeMenuPopover(controller: MenuBarController) -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        let menuController = NSHostingController(
            rootView: BarredMenuView(onClose: { [weak popover] in
                popover?.performClose(nil)
            })
            .environment(controller)
        )
        menuController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = menuController
        popover.contentSize = menuController.view.fittingSize
        return popover
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let optionHeld = event?.modifierFlags.contains(.option) == true
        let clickTogglesBar = controller.preferences.showBarredBarOnClick

        let shouldToggleBar = Self.shouldToggleBar(optionHeld: optionHeld, showBarredBarOnClick: clickTogglesBar)

        if shouldToggleBar {
            controller.accessibilityService.checkTrust()
            if !controller.accessibilityService.isTrusted {
                Self.logger.info("AXIsProcessTrusted = false, requesting trust")
                controller.accessibilityService.requestTrust()
            }
            Task { await controller.toggleBarredBar() }
        } else {
            togglePopover(sender)
        }
    }

    nonisolated static func shouldToggleBar(optionHeld: Bool, showBarredBarOnClick: Bool) -> Bool {
        showBarredBarOnClick && !optionHeld
    }

    #if DEBUG
        private func runSectionDiagnostic() async {
            guard let divider = controller.sectionDivider as? SectionDivider else { return }
            divider.setUp(onToggle: {})
            var snapshots = [[String: Any]]()
            var expected: Set<String>?
            var passed = true
            for cycle in 0 ..< 12 {
                divider.collapse()
                if cycle % 4 > 0 {
                    try? await Task.sleep(for: .milliseconds((cycle % 4) * 50))
                }
                snapshots.append(divider.diagnosticSnapshot(label: "revealed-\(cycle)"))
                let success = await divider.expand()
                try? await Task.sleep(for: .milliseconds(300))
                var snapshot = divider.diagnosticSnapshot(label: "hidden-\(cycle)")
                snapshot["success"] = success
                snapshots.append(snapshot)
                let selected = divider.hiddenBundleIdentifiers
                if expected == nil {
                    expected = selected
                }
                passed = passed && success && !selected.isEmpty && selected == expected
                let report: [String: Any] = ["passed": passed, "completedCycles": cycle + 1, "snapshots": snapshots]
                if let data = try? JSONSerialization.data(
                    withJSONObject: report,
                    options: [.prettyPrinted, .sortedKeys]
                ) {
                    try? data.write(to: URL(fileURLWithPath: "/private/tmp/barred-layout-check.json"), options: .atomic)
                }
            }
            divider.collapse()
            NSApp.terminate(nil)
        }
    #endif

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    func applicationWillTerminate(_: Notification) {
        controller.restoreAll()
    }

    nonisolated static func shouldPresentOnboarding(defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: hasPresentedOnboardingKey) else { return false }

        defaults.set(true, forKey: hasPresentedOnboardingKey)
        return defaults.data(forKey: PreferencesStore.defaultsKey) == nil
    }
}

@main
struct BarredApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.controller)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
