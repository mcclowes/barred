import SwiftUI

struct MenuBarItemRow: View {
    let item: MenuBarItem
    let visibility: ItemVisibility
    let onVisibilityChanged: (ItemVisibility) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Picker("", selection: Binding(
                get: { visibility },
                set: { onVisibilityChanged($0) }
            )) {
                Label("Visible", systemImage: "eye")
                    .tag(ItemVisibility.alwaysShow)
                Label("Barman bar", systemImage: "menubar.arrow.up.rectangle")
                    .tag(ItemVisibility.barmanBar)
                Label("Hidden", systemImage: "eye.slash")
                    .tag(ItemVisibility.hidden)
            }
            .pickerStyle(.menu)
            .frame(width: 140)
        }
        .padding(.vertical, 4)
    }
}
