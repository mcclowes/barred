import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = MenuBarController.shared
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Create the main Barred status item
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

        // Set up the popover for option+click
        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: BarredMenuView())

        // Create the divider status item for the expand/collapse trick
        controller.sectionDivider.setUp()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let optionHeld = event?.modifierFlags.contains(.option) == true

        if optionHeld {
            togglePopover(sender)
            return
        }

        controller.accessibilityService.checkTrust()
        if !controller.accessibilityService.isTrusted {
            print("[Barred] AXIsProcessTrusted = false, requesting trust")
            controller.accessibilityService.requestTrust()
        }

        controller.toggleBarredBar()
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

    @objc private func quitApp() {
        controller.restoreAll()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.restoreAll()
    }
}

@main
struct BarredApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }
}
