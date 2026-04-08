import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = MenuBarController.shared
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Create the main Barman status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "line.3.horizontal.decrease",
                accessibilityDescription: "Barman"
            )
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }

        // Set up the popover for option+click
        popover = NSPopover()
        popover.contentSize = NSSize(width: 240, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: BarmanMenuView())

        // Create the divider status item for the expand/collapse trick
        controller.sectionDivider.setUp()
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let optionHeld = event?.modifierFlags.contains(.option) == true

        if optionHeld {
            togglePopover(sender)
        } else {
            controller.toggleBarmanBar()
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

    @objc func toggleBarmanBarFromDivider() {
        controller.toggleBarmanBar()
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
struct BarmanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
