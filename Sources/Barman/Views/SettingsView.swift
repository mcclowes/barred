import SwiftUI

struct SettingsView: View {
    @State private var controller = MenuBarController.shared

    var body: some View {
        TabView {
            ItemsSettingsView(controller: controller)
                .tabItem {
                    Label("Menu bar items", systemImage: "menubar.rectangle")
                }

            GeneralSettingsView(controller: controller)
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 400)
    }
}

struct ItemsSettingsView: View {
    let controller: MenuBarController

    var body: some View {
        VStack(alignment: .leading) {
            if !controller.accessibilityService.isTrusted {
                OnboardingView(controller: controller)
            } else if controller.detectedItems.isEmpty {
                ContentUnavailableView(
                    "No items detected",
                    systemImage: "menubar.rectangle",
                    description: Text("Menu bar items will appear here once detected.")
                )
            } else {
                List(controller.detectedItems) { item in
                    MenuBarItemRow(
                        item: item,
                        visibility: controller.visibility(for: item)
                    ) { newVisibility in
                        controller.setVisibility(newVisibility, for: item)
                    }
                }
            }
        }
        .padding()
    }
}

struct GeneralSettingsView: View {
    let controller: MenuBarController

    var body: some View {
        Form {
            Toggle("Show Barman bar on click", isOn: Binding(
                get: { controller.preferences.showBarmanBarOnClick },
                set: { newValue in
                    controller.preferences.showBarmanBarOnClick = newValue
                    controller.preferencesStore.save()
                }
            ))

            HStack {
                Text("Auto-hide delay")
                Slider(
                    value: Binding(
                        get: { controller.preferences.autoHideDelay },
                        set: { newValue in
                            controller.preferences.autoHideDelay = newValue
                            controller.preferencesStore.save()
                        }
                    ),
                    in: 1...15,
                    step: 1
                )
                Text("\(Int(controller.preferences.autoHideDelay))s")
                    .monospacedDigit()
                    .frame(width: 30)
            }
        }
        .padding()
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)

            Text("Barman")
                .font(.title)
                .fontWeight(.bold)

            Text("Menu bar manager for macOS")
                .foregroundStyle(.secondary)

            Text("v1.0.0")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
