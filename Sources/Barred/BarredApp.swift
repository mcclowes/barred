import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.topthird.inset.filled",
                accessibilityDescription: "Barred"
            )
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: BarredMenuView()
                .environment(controller)
        )

        controller.start()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let optionHeld = event?.modifierFlags.contains(.option) == true
        let clickTogglesBar = controller.preferences.showBarredBarOnClick

        // Normal click: toggle bar (or popover if showBarredBarOnClick is off)
        // Option-click: the opposite action
        let shouldToggleBar = clickTogglesBar != optionHeld

        if shouldToggleBar {
            controller.accessibilityService.checkTrust()
            if !controller.accessibilityService.isTrusted {
                #if DEBUG
                    print("[Barred] AXIsProcessTrusted = false, requesting trust")
                #endif
                controller.accessibilityService.requestTrust()
            }
            controller.toggleBarredBar()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    @objc func toggleBarredBarFromDivider() {
        controller.toggleBarredBar()
    }

    func applicationWillTerminate(_: Notification) {
        controller.restoreAll()
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
