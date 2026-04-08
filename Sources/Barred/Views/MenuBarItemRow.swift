import SwiftUI

struct MenuBarItemRow: View {
    let item: MenuBarItem
    let showIndex: Bool

    var body: some View {
        HStack(spacing: 10) {
            if let icon = item.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "app.dashed")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName(showIndex: showIndex))
                    .font(.body)
                    .fontWeight(.medium)

                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
