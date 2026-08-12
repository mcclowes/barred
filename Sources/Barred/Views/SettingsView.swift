import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(MenuBarController.self) private var controller

    var body: some View {
        TabView {
            ItemsSettingsView()
                .tabItem {
                    Label("Menu bar items", systemImage: "menubar.rectangle")
                }

            GeneralSettingsView()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            AboutView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(minWidth: 500, idealWidth: 500, minHeight: 450, idealHeight: 550)
    }
}

struct ItemsSettingsView: View {
    @Environment(MenuBarController.self) private var controller

    private var visibleItems: [MenuBarItem] {
        controller.detectedItems
            .filter { !$0.isHidden }
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
    }

    private var hiddenItems: [MenuBarItem] {
        controller.detectedItems
            .filter(\.isHidden)
            .sorted { $0.frame.origin.x < $1.frame.origin.x }
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
        let visible = visibleItems
        let hidden = hiddenItems

        return VStack(alignment: .leading) {
            if !controller.accessibilityService.isTrusted {
                OnboardingView()
            } else if controller.detectedItems.isEmpty {
                ContentUnavailableView(
                    "No items detected",
                    systemImage: "menubar.rectangle",
                    description: Text("Menu bar items will appear here once detected.")
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        "Drag items in this list to rearrange them, or \u{2318}-drag icons directly in the menu bar. " +
                            "Items to the left of the Barred divider (|) will be hidden."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)

                    List {
                        Section {
                            ForEach(visible) { item in
                                MenuBarItemRow(item: item, showIndex: shouldShowIndex(for: item))
                            }
                            .onMove { source, destination in
                                Task { @MainActor in
                                    await controller.moveItem(
                                        from: source,
                                        to: destination,
                                        in: visible
                                    )
                                }
                            }
                        } header: {
                            Label("Visible", systemImage: "eye")
                        }

                        if !hidden.isEmpty {
                            Section {
                                ForEach(hidden) { item in
                                    MenuBarItemRow(item: item, showIndex: shouldShowIndex(for: item))
                                }
                            } header: {
                                Label("Hidden", systemImage: "eye.slash")
                            }
                        }
                    }
                    .disabled(controller.isMovingItem)
                }
            }
        }
        .padding()
    }
}

struct GeneralSettingsView: View {
    @Environment(MenuBarController.self) private var controller

    var body: some View {
        @Bindable var controller = controller

        Form {
            LaunchAtLoginToggle("Launch at login")

            Toggle("Show Barred bar on click", isOn: $controller.preferences.showBarredBarOnClick)

            HStack {
                Text("Auto-hide delay")
                Slider(
                    value: $controller.preferences.autoHideDelay,
                    in: 1 ... 15,
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

struct LaunchAtLoginToggle: View {
    @Environment(MenuBarController.self) private var controller
    @State private var isUpdating = false
    @State private var errorMessage: String?

    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        @Bindable var controller = controller

        Toggle(title, isOn: $controller.preferences.launchAtLogin)
            .onChange(of: controller.preferences.launchAtLogin) { oldValue, newValue in
                guard !isUpdating else { return }
                isUpdating = true
                defer { isUpdating = false }
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    controller.preferences.launchAtLogin = oldValue
                }
            }
            .alert(
                "Couldn't update Login Items",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: {
                        if !$0 {
                            errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "menubar.arrow.up.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("Barred")
                .font(.title)
                .fontWeight(.bold)

            Text("Menu bar manager for macOS")
                .foregroundStyle(.secondary)

            Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
