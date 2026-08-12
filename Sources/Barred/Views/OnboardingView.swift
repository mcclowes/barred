import SwiftUI

struct OnboardingView: View {
    @Environment(MenuBarController.self) private var controller

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            Text("Accessibility access required")
                .font(.headline)

            Text("Barred needs accessibility access to detect and manage menu bar items from other apps.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Open System Settings") {
                    openAccessibilitySettings()
                }

                Button("Request access") {
                    controller.accessibilityService.requestTrust()
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Check again") {
                controller.accessibilityService.checkTrust()
            }
            .font(.caption)

            Divider()

            VStack(spacing: 8) {
                Label("Always have Barred ready", systemImage: "bolt.circle")
                    .font(.headline)

                Text("Recommended so your menu bar stays organised after every restart.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                LaunchAtLoginToggle("Launch Barred at login")
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
