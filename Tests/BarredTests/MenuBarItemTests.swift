import AppKit
@testable import Barred
import Darwin
import Testing

struct MenuBarItemTests {
    private func makeItem(
        pid: Int32 = 123,
        appName: String = "TestApp",
        bundleIdentifier: String? = "com.test.app",
        title: String? = "Test",
        frame: CGRect = .zero,
        itemIndex: Int = 0
    ) -> MenuBarItem {
        MenuBarItem(
            pid: pid,
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            title: title,
            windowID: 1,
            frame: frame,
            itemIndex: itemIndex,
            axElement: nil
        )
    }

    @Test("displayName returns title when present")
    func displayNameWithTitle() {
        let item = makeItem(title: "Wi-Fi")
        #expect(item.displayName == "Wi-Fi")
    }

    @Test("displayName falls back to appName with index")
    func displayNameWithoutTitle() {
        let item = makeItem(appName: "Finder", title: .none, itemIndex: 2)
        #expect(item.displayName == "Finder #3")
    }

    @Test("displayName falls back when title is empty")
    func displayNameWithEmptyTitle() {
        let item = makeItem(appName: "Finder", title: "", itemIndex: 0)
        #expect(item.displayName == "Finder #1")
    }

    @Test("subtitle returns appName when title is present")
    func subtitleWithTitle() {
        let item = makeItem(appName: "Control Center", title: "Wi-Fi")
        #expect(item.subtitle == "Control Center")
    }

    @Test("subtitle is nil when no title")
    func subtitleWithoutTitle() {
        let item = makeItem(title: .none)
        #expect(item.subtitle == nil)
    }

    @Test("persistenceKey uses bundle identifier and title")
    func persistenceKeyWithBundle() {
        let item = makeItem(bundleIdentifier: "com.apple.wifi", title: "Wi-Fi", itemIndex: 0)
        #expect(item.persistenceKey == "com.apple.wifi:Wi-Fi")
    }

    @Test("persistenceKey falls back to pid when no bundle")
    func persistenceKeyWithoutBundle() {
        let item = makeItem(pid: 456, bundleIdentifier: .none, title: "Item", itemIndex: 0)
        #expect(item.persistenceKey == "pid-456:Item")
    }

    @Test("persistenceKey falls back to item index when no title")
    func persistenceKeyWithoutTitle() {
        let item = makeItem(bundleIdentifier: "com.test", title: .none, itemIndex: 3)
        #expect(item.persistenceKey == "com.test:item-3")
    }

    @Test("equality is based on id (bundleIdentifier + title)")
    func equality() {
        let a = makeItem(pid: 1, appName: "A", bundleIdentifier: "com.test", title: "X", itemIndex: 0)
        let b = makeItem(pid: 2, appName: "B", bundleIdentifier: "com.test", title: "X", itemIndex: 0)
        #expect(a == b)
    }

    @Test("different ids are not equal")
    func inequality() {
        let a = makeItem(bundleIdentifier: "com.test", title: "X")
        let b = makeItem(bundleIdentifier: "com.test", title: "Y")
        #expect(a != b)
    }

    @Test("isHidden reports true for items pushed far off-screen")
    func isHiddenOffscreen() {
        let offscreen = CGRect(x: -50000, y: 0, width: 20, height: 24)
        let item = makeItem(frame: offscreen)
        #expect(item.isHidden == true)
    }

    @Test("isHidden is false for items inside a connected screen frame")
    func isHiddenOnScreen() {
        guard let main = NSScreen.screens.first else {
            // Headless environment — falls back to `< 0` check, which `.zero`
            // does not satisfy, so `.zero` should still be considered visible.
            let item = makeItem(frame: .zero)
            #expect(item.isHidden == false)
            return
        }
        let onScreen = CGRect(
            origin: CGPoint(x: main.frame.midX, y: main.frame.midY),
            size: CGSize(width: 20, height: 24)
        )
        let item = makeItem(frame: onScreen)
        #expect(item.isHidden == false)
    }
}
