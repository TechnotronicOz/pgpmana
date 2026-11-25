import SwiftUI
import PgpassKit

enum EditorRequest: Identifiable {
    case add
    case edit(PgpassLine.ID)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let lineID): return lineID.uuidString
        }
    }
}

struct ConnectionTestRequest: Identifiable {
    let id = UUID()
    let entry: PgpassEntry
}

struct ContentView: View {
    @Environment(PgpassStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager

    @State private var filter: SidebarFilter = .all
    @State private var selection: PgpassLine.ID?
    @State private var editor: EditorRequest?
    @State private var showInspector = true
    @State private var showAbout = false
    @State private var showFixOrder = false
    @State private var connectionTest: ConnectionTestRequest?

    var body: some View {
        NavigationSplitView {
            SidebarView(filter: $filter)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                if store.permissionsTooOpen {
                    Banner(
                        systemImage: "exclamationmark.triangle",
                        message: "This file is mode \(store.modeString). libpq ignores a password file that group or others can access."
                    ) {
                        Button("Fix to 0600") { store.fixPermissions() }
                            .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                    }
                }
                if store.changedOnDisk {
                    Banner(
                        systemImage: "arrow.triangle.2.circlepath",
                        message: "\(store.displayPath) changed on disk after it was opened."
                    ) {
                        Button("Reload") { store.reload() }
                            .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                        Button("Overwrite") { store.save(overwrite: true) }
                            .buttonStyle(PillButtonStyle(kind: .primary, compact: true))
                    }
                }
                if let notice = store.notice {
                    Banner(systemImage: "arrow.clockwise", message: notice) {
                        Button("Dismiss") { store.notice = nil }
                            .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                    }
                }
                if let message = store.errorMessage {
                    Banner(systemImage: "xmark.octagon", message: message) {
                        Button("Dismiss") { store.errorMessage = nil }
                            .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                    }
                }
                EntryListView(
                    filter: filter,
                    selection: $selection,
                    onEdit: { editor = .edit($0) },
                    onTest: testConnection
                )
            }
            .background(Theme.graphite)
            .inspector(isPresented: $showInspector) {
                inspector
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(Theme.smoke.ignoresSafeArea())
                    .inspectorColumnWidth(min: 290, ideal: 320, max: 420)
            }
        }
        .navigationTitle(store.displayPath)
        .navigationSubtitle(subtitle)
        .toolbarBackground(Theme.smoke, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if store.fileExists && !store.permissionsTooOpen {
                    ModeChip(mode: store.modeString)
                }
                Button { store.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }
                    .help("Save to \(store.displayPath) (⌘S)")
                    .disabled(!store.isDirty)
                Button { showFixOrder = true } label: { Label("Fix Order", systemImage: "arrow.up.arrow.down") }
                    .help(store.shadowMap.isEmpty ? "No entries are hidden" : "Reorder so no entry is hidden (⌥⌘F)")
                    .disabled(store.shadowMap.isEmpty)
                Button { openWindow(id: "match-tester") } label: { Label("Match Tester", systemImage: "text.alignleft") }
                    .help("See which entry a connection would use (⇧⌘T)")
                Button { editor = .add } label: {
                    Label("Add entry", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.primaryPill)
                .help("Add an entry (⌘N)")
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                    .help(showInspector ? "Hide details" : "Show details")
            }
        }
        .sheet(item: $editor) { request in
            EntryEditorSheet(request: request, selection: selection) { selection = $0 }
                .environment(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pgpmanaAddEntry)) { _ in
            editor = .add
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pgpmanaShowAbout)) { _ in
            showAbout = true
        }
        .sheet(isPresented: $showFixOrder) {
            FixOrderSheet()
                .environment(store)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pgpmanaFixOrder)) { _ in
            if !store.shadowMap.isEmpty { showFixOrder = true }
        }
        .sheet(item: $connectionTest) { request in
            ConnectionTestSheet(entry: request.entry)
        }
        .onAppear { store.undoManager = undoManager }
        .onChange(of: undoManager) { _, newValue in store.undoManager = newValue }
    }

    private func testConnection(_ id: PgpassLine.ID) {
        if let entry = store.line(id)?.entry {
            connectionTest = ConnectionTestRequest(entry: entry)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        if let id = selection, store.line(id)?.entry != nil {
            EntryDetailView(
                lineID: id,
                onEdit: { editor = .edit(id) },
                onTest: { testConnection(id) },
                onFixOrder: { showFixOrder = true },
                onSelect: { selection = $0 }
            )
        } else {
            VStack(spacing: 8) {
                Image(systemName: "key")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Theme.pewter)
                Text("No entry selected")
                    .font(Theme.sans(14, .medium))
                    .foregroundStyle(Theme.coolWhite)
                Text("Pick an entry to see its details.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.pewter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var subtitle: String {
        guard store.fileExists else { return "File doesn't exist yet. Saving creates it." }
        let comments = store.lines.filter { if case .comment = $0.kind { return true } else { return false } }.count
        var parts = ["\(store.entries.count) entries", "\(comments) comments"]
        if store.isDirty {
            parts.append("unsaved changes")
        } else if let saved = store.lastSaved {
            parts.append("saved \(saved.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct Banner<Actions: View>: View {
    let systemImage: String
    let message: String
    let actions: Actions

    init(systemImage: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.systemImage = systemImage
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.solar)
            Text(message)
                .font(Theme.sans(13, .medium))
                .foregroundStyle(Theme.brightWhite)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.ash)
        .hairline(.bottom)
    }
}
