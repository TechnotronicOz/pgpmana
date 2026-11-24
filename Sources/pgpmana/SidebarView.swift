import SwiftUI
import PgpassKit

enum SidebarFilter: Hashable {
    case all
    case wildcards
    case neverUsed
    case host(String)
}

struct SidebarView: View {
    @Environment(PgpassStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Binding var filter: SidebarFilter

    var body: some View {
        let entries = store.entries

        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow("Library", color: Theme.pewter)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                    SidebarRow(title: "All entries", count: entries.count, isSelected: filter == .all) {
                        filter = .all
                    }
                    SidebarRow(title: "Uses wildcards", count: entries.filter(\.usesWildcard).count, isSelected: filter == .wildcards) {
                        filter = .wildcards
                    }
                    SidebarRow(title: "Never used", count: store.shadowMap.count, highlightCount: true, isSelected: filter == .neverUsed) {
                        filter = .neverUsed
                    }

                    Eyebrow("Hosts", color: Theme.pewter)
                        .padding(.horizontal, 8)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                    ForEach(store.hosts, id: \.self) { host in
                        SidebarRow(title: host == "*" ? "* (any host)" : host, isSelected: filter == .host(host)) {
                            filter = .host(host)
                        }
                    }
                }
                .padding(10)
            }

            Button {
                openWindow(id: "match-tester")
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "text.alignleft")
                    Text("Test a connection")
                }
                .font(Theme.sans(13, .medium))
                .foregroundStyle(Theme.amber)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.midBorder))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.smoke.ignoresSafeArea())
    }
}

private struct SidebarRow: View {
    let title: String
    var count: Int? = nil
    var highlightCount = false
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 6)
                if let count {
                    let emphasized = highlightCount && count > 0
                    Text("\(count)")
                        .font(Theme.sans(13, emphasized ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(emphasized ? Theme.solar : (isSelected ? Theme.softStone : Theme.pewter))
                }
            }
            .font(Theme.sans(13))
            .foregroundStyle(isSelected ? Theme.brightWhite : Theme.silverMist)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Theme.flint : (hovering ? Theme.ash : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
