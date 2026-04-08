import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let controller = MenuBarController.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "line.3.horizontal.decrease",
                accessibilityDescription: "Barman"
            )
        }

        buildMenu()
    }

    func buildMenu() {
        let menu = NSMenu()

        let toggleTitle = controller.isBarmanBarVisible ? "Hide Barman bar" : "Show Barman bar"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleBarmanBar), keyEquivalent: "b")
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        if !controller.accessibilityService.isTrusted {
            let axItem = NSMenuItem(title: "Grant accessibility access...", action: #selector(requestAccessibility), keyEquivalent: "")
            axItem.target = self
            menu.addItem(axItem)
            menu.addItem(.separator())
        }

        let countItem = NSMenuItem(title: "\(controller.detectedItems.count) menu bar items detected", action: nil, keyEquivalent: "")
        countItem.isEnabled = false
        menu.addItem(countItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit Barman", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func toggleBarmanBar() {
        controller.toggleBarmanBar()
        buildMenu()
    }

    @objc private func requestAccessibility() {
        controller.accessibilityService.requestTrust()
    }

    @objc func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Barman Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 500, height: 400))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct BarmanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
