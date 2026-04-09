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
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
