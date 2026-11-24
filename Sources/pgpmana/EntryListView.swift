import SwiftUI
import UniformTypeIdentifiers
import PgpassKit

enum Columns {
    static let inset: CGFloat = 16
    static let spacing: CGFloat = 8
    static let grip: CGFloat = 12
    static let number: CGFloat = 30
    static let port: CGFloat = 56
    static let database: CGFloat = 140
    static let user: CGFloat = 140
    static let password: CGFloat = 72
    /// Where text after the grip and number columns starts.
    static var contentLeading: CGFloat { inset + grip + number + spacing * 2 }
}

struct EntryListView: View {
    @Environment(PgpassStore.self) private var store
    let filter: SidebarFilter
    @Binding var selection: PgpassLine.ID?
    var onEdit: (PgpassLine.ID) -> Void

    @State private var search = ""
    @State private var dragging: PgpassLine.ID?
    @FocusState private var focused: Bool

    /// Drag to reorder only when every line is shown, so rows map to file lines.
    private var canReorder: Bool { filter == .all && search.isEmpty }

    var body: some View {
        let shadowMap = store.shadowMap
        let visible = visibleLines(shadowMap: shadowMap)

        VStack(spacing: 0) {
            ColumnHeader()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { line in
                            row(for: line, shadowMap: shadowMap)
                                .id(line.id)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: selection) { _, newValue in
                    if let newValue { proxy.scrollTo(newValue) }
                }
            }
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onMoveCommand { moveSelection($0, in: visible) }
            .onDeleteCommand(perform: deleteSelection)
            .onKeyPress(.return) {
                guard let id = selection, store.line(id)?.entry != nil else { return .ignored }
                onEdit(id)
                return .handled
            }

            Text(canReorder
                 ? "libpq uses the first entry that matches. Drag rows to reorder; put specific entries above wildcards."
                 : "Showing a filtered view. Choose All entries with no search to reorder.")
                .font(Theme.sans(12))
                .foregroundStyle(Theme.stone)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Columns.inset)
                .padding(.vertical, 10)
                .hairline(.top)
        }
        .background(Theme.graphite)
        .searchable(text: $search, placement: .toolbar, prompt: "Filter host, db, user")
    }

    // MARK: Rows

    @ViewBuilder
    private func row(for line: PgpassLine, shadowMap: [PgpassLine.ID: PgpassLine.ID]) -> some View {
        switch line.kind {
        case .entry(let entry):
            EntryRow(
                number: store.entryNumber(for: line.id) ?? 0,
                entry: entry,
                isShadowed: shadowMap[line.id] != nil,
                isSelected: selection == line.id,
                showsGrip: canReorder
            )
            .contentShape(Rectangle())
            .onTapGesture {
                selection = line.id
                focused = true
            }
            .simultaneousGesture(TapGesture(count: 2).onEnded { onEdit(line.id) })
            .contextMenu { contextMenu(for: line) }
            .modifier(Reorderable(enabled: canReorder, lineID: line.id, dragging: $dragging, store: store))
        case .comment(let text):
            Text(text)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.stone)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, Columns.contentLeading)
                .padding(.trailing, Columns.inset)
                .padding(.top, 12)
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .contextMenu { contextMenu(for: line) }
                .modifier(Reorderable(enabled: canReorder, lineID: line.id, dragging: $dragging, store: store))
        case .blank:
            Color.clear
                .frame(height: 6)
                .contentShape(Rectangle())
                .contextMenu { contextMenu(for: line) }
                .modifier(Reorderable(enabled: canReorder, lineID: line.id, dragging: $dragging, store: store))
        case .unparsed(let text):
            HStack(spacing: 6) {
                Image(systemName: "questionmark.diamond")
                Text(text).lineLimit(1)
            }
            .font(Theme.mono(11))
            .foregroundStyle(Theme.pewter)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Columns.contentLeading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .help("libpq can't read this line: it needs four ':' separators.")
            .contextMenu { contextMenu(for: line) }
            .modifier(Reorderable(enabled: canReorder, lineID: line.id, dragging: $dragging, store: store))
        }
    }

    @ViewBuilder
    private func contextMenu(for line: PgpassLine) -> some View {
        if line.entry != nil {
            Button("Edit…") { onEdit(line.id) }
            Button("Duplicate") { selection = store.duplicate(line.id) }
            Divider()
            Button("Delete", role: .destructive) {
                store.delete(line.id)
                if selection == line.id { selection = nil }
            }
        } else {
            Button("Delete Line", role: .destructive) { store.delete(line.id) }
        }
    }

    // MARK: Filtering and keyboard

    private func visibleLines(shadowMap: [PgpassLine.ID: PgpassLine.ID]) -> [PgpassLine] {
        if canReorder { return store.lines }
        return store.lines.filter { line in
            guard let e = line.entry else { return false }
            let passes: Bool
            switch filter {
            case .all: passes = true
            case .wildcards: passes = e.usesWildcard
            case .neverUsed: passes = shadowMap[line.id] != nil
            case .host(let host): passes = e.host == host
            }
            guard passes else { return false }
            guard !search.isEmpty else { return true }
            return e.matchFields.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection, in visible: [PgpassLine]) {
        let ids = visible.filter { $0.entry != nil }.map(\.id)
        guard !ids.isEmpty else { return }
        guard let current = selection, let i = ids.firstIndex(of: current) else {
            selection = ids.first
            return
        }
        switch direction {
        case .up: selection = ids[max(i - 1, 0)]
        case .down: selection = ids[min(i + 1, ids.count - 1)]
        default: break
        }
    }

    private func deleteSelection() {
        guard let id = selection else { return }
        store.delete(id)
        selection = nil
    }
}

// MARK: - Drag to reorder

@MainActor
private struct Reorderable: ViewModifier {
    let enabled: Bool
    let lineID: PgpassLine.ID
    @Binding var dragging: PgpassLine.ID?
    let store: PgpassStore

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = lineID
                    return NSItemProvider(object: lineID.uuidString as NSString)
                }
                .onDrop(of: [.plainText, .text], delegate: RowDropDelegate(target: lineID, dragging: $dragging, store: store))
        } else {
            content
        }
    }
}

@MainActor
private struct RowDropDelegate: DropDelegate {
    let target: PgpassLine.ID
    @Binding var dragging: PgpassLine.ID?
    let store: PgpassStore

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target else { return }
        withAnimation(.easeInOut(duration: 0.12)) {
            store.moveLive(dragging, to: target)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}

// MARK: - Header and row

private struct ColumnHeader: View {
    var body: some View {
        HStack(spacing: Columns.spacing) {
            Color.clear.frame(width: Columns.grip, height: 1)
            Text("LINE").frame(width: Columns.number, alignment: .leading)
            Text("HOST").frame(maxWidth: .infinity, alignment: .leading)
            Text("PORT").frame(width: Columns.port, alignment: .leading)
            Text("DATABASE").frame(width: Columns.database, alignment: .leading)
            Text("USER").frame(width: Columns.user, alignment: .leading)
            Text("PASSWORD").frame(width: Columns.password, alignment: .leading)
        }
        .font(Theme.mono(10, .medium))
        .tracking(1.6)
        .foregroundStyle(Theme.stone)
        .padding(.horizontal, Columns.inset)
        .padding(.vertical, 10)
        .background(Theme.graphite)
        .hairline(.bottom)
    }
}

struct EntryRow: View {
    let number: Int
    let entry: PgpassEntry
    let isShadowed: Bool
    let isSelected: Bool
    var showsGrip = true

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Columns.spacing) {
            GripDots()
                .frame(width: Columns.grip)
                .opacity(showsGrip ? 1 : 0)
            Text("\(number)")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.pewter)
                .frame(width: Columns.number, alignment: .leading)
            HStack(spacing: 6) {
                cell(entry.host, primary: true)
                if isShadowed { NeverUsedBadge() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cell(entry.port, mono: true)
                .frame(width: Columns.port, alignment: .leading)
            cell(entry.database)
                .frame(width: Columns.database, alignment: .leading)
            cell(entry.username)
                .frame(width: Columns.user, alignment: .leading)
            Text("••••••")
                .font(Theme.mono(12))
                .foregroundStyle(Theme.pewter)
                .frame(width: Columns.password, alignment: .leading)
        }
        .padding(.horizontal, Columns.inset)
        .padding(.vertical, 9)
        .background(isSelected ? Theme.ash : (hovering ? Theme.smoke : Color.clear))
        .opacity(isShadowed ? 0.7 : 1)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func cell(_ value: String, primary: Bool = false, mono: Bool = false) -> some View {
        Text(value)
            .font(mono ? Theme.mono(12) : Theme.sans(13))
            .foregroundStyle(value == "*" ? Theme.pewter : (primary ? Theme.brightWhite : Theme.silverMist))
            .lineLimit(1)
            .truncationMode(.middle)
    }
}
