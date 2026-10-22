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

        popover = NSPopover()
        popover.behavior = .transient
        let menuController = NSHostingController(
            rootView: BarredMenuView(onClose: { [weak self] in
                self?.popover.performClose(nil)
            })
            .environment(controller)
        )
        menuController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = menuController

        controller.start()

        if Self.shouldPresentOnboarding() {
            DispatchQueue.main.async {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
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
