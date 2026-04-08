import ServiceManagement
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

    private var visibleItems: [MenuBarItem] {
        controller.detectedItems.filter { !$0.isHidden }
    }

    private var hiddenItems: [MenuBarItem] {
        controller.detectedItems.filter { $0.isHidden }
    }

    private var appsWithMultipleItems: Set<String> {
        let appNames = controller.detectedItems.map(\.appName)
        let counts = Dictionary(grouping: appNames, by: { $0 }).filter { $0.value.count > 1 }
        return Set(counts.keys)
    }

    private func shouldShowIndex(for item: MenuBarItem) -> Bool {
        appsWithMultipleItems.contains(item.appName)
    }

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
                VStack(alignment: .leading, spacing: 8) {
                    Text("⌘-drag menu bar icons to rearrange them. Items to the left of the Barred divider (|) will be hidden.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    List {
                        Section {
                            ForEach(visibleItems) { item in
                                MenuBarItemRow(item: item, showIndex: shouldShowIndex(for: item))
                            }
                        } header: {
                            Label("Visible", systemImage: "eye")
                        }

                        if !hiddenItems.isEmpty {
                            Section {
                                ForEach(hiddenItems) { item in
                                    MenuBarItemRow(item: item, showIndex: shouldShowIndex(for: item))
                                }
                            } header: {
                                Label("Hidden", systemImage: "eye.slash")
                            }
                        }
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
            Toggle("Launch at login", isOn: Binding(
                get: { controller.preferences.launchAtLogin },
                set: { newValue in
                    controller.preferences.launchAtLogin = newValue
                    controller.preferencesStore.save()
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        // Revert on failure
                        controller.preferences.launchAtLogin = !newValue
                        controller.preferencesStore.save()
                    }
                }
            ))

            Toggle("Show Barred bar on click", isOn: Binding(
                get: { controller.preferences.showBarredBarOnClick },
                set: { newValue in
                    controller.preferences.showBarredBarOnClick = newValue
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

            Text("Barred")
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
