import SwiftUI

struct BarredMenuView: View {
    @State private var controller = MenuBarController.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                controller.toggleBarredBar()
            }) {
                Label(
                    controller.isBarredBarVisible ? "Hide Barred bar" : "Show Barred bar",
                    systemImage: controller.isBarredBarVisible ? "eye.slash" : "eye"
                )
            }
            .buttonStyle(.plain)

            Divider()

            if !controller.accessibilityService.isTrusted {
                Button(action: { controller.accessibilityService.requestTrust() }) {
                    Label("Grant accessibility access...", systemImage: "lock.shield")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)

                Divider()
            }

            Text("\(controller.detectedItems.count) menu bar items detected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("⌘+drag a menu bar icon to move it out of hidden")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Divider()

            SettingsLink {
                Label("Settings...", systemImage: "gear")
            }
            .buttonStyle(.plain)

            Divider()

            Button(action: {
                controller.restoreAll()
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit Barred", systemImage: "xmark.circle")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 240)
    }
}
