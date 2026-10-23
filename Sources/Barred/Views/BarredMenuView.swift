import SwiftUI

struct BarredMenuView: View {
    @Environment(MenuBarController.self) private var controller
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .foregroundStyle(.secondary)
                Text("Barred")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            VStack(spacing: 2) {
                Button {
                    Task { await controller.toggleBarredBar() }
                    onClose()
                } label: {
                    menuRow(
                        controller.isBarredBarVisible ? "Hide Barred bar" : "Show Barred bar",
                        icon: controller.isBarredBarVisible ? "eye.slash" : "eye"
                    )
                }

                if !controller.accessibilityService.isTrusted {
                    Button {
                        onClose()
                        controller.accessibilityService.requestTrust()
                    } label: {
                        menuRow("Grant accessibility access...", icon: "lock.shield")
                    }
                    .foregroundStyle(.orange)
                }

                Divider()
                    .padding(.vertical, 4)

                SettingsLink {
                    menuRow("Settings...", icon: "gear")
                }

                Button {
                    controller.restoreAll()
                    NSApplication.shared.terminate(nil)
                } label: {
                    menuRow("Quit Barred", icon: "power")
                }
            }
            .buttonStyle(MenuButtonStyle())
            .padding(.vertical, 6)
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 4) {
                if let error = controller.hidingError {
                    Text(error)
                        .foregroundStyle(.orange)
                }
                Text("\(controller.detectedItems.count) menu bar items detected")
                Text(SectionDivider.usesBoundedSection
                    ? "\u{2318}-drag icons between the two lines to hide them."
                    : "\u{2318}-drag icons across the divider to hide or show them.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .frame(width: 240)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func menuRow(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            Text(title)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct MenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.1) : .clear)
            )
    }
}
