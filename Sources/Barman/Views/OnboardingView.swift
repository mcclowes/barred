import SwiftUI

struct OnboardingView: View {
    let controller: MenuBarController

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Accessibility access required")
                .font(.headline)

            Text("Barman needs accessibility access to detect and manage menu bar items from other apps.")
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
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
