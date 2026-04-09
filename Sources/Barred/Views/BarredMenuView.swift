import SwiftUI

struct BarredMenuView: View {
    @Environment(MenuBarController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(
                controller.isBarredBarVisible ? "Hide Barred bar" : "Show Barred bar",
                systemImage: controller.isBarredBarVisible ? "eye.slash" : "eye"
            ) {
                controller.toggleBarredBar()
            }
            .buttonStyle(.plain)

            Divider()

            if !controller.accessibilityService.isTrusted {
                Button("Grant accessibility access...", systemImage: "lock.shield") {
                    controller.accessibilityService.requestTrust()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)

                Divider()
            }

            Text("\(controller.detectedItems.count) menu bar items detected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\u{2318}+drag a menu bar icon to move it out of hidden")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gear")
            }
            .buttonStyle(.plain)

            Divider()

            Button("Quit Barred", systemImage: "xmark.circle") {
                controller.restoreAll()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 240)
    }
}
