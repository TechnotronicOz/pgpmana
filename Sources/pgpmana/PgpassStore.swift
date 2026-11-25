import SwiftUI
import PgpassKit

enum InsertPosition: Hashable {
    case top
    case bottom
    case before(PgpassLine.ID)
}

struct CandidateAnalysis {
    /// 1-based entry number the candidate would have.
    var entryNumber: Int
    /// 1-based number of the earlier entry that would hide it.
    var shadowedBy: Int?
    /// 1-based numbers of later entries it would hide.
    var hides: [Int]
}

@MainActor
@Observable
final class PgpassStore {
    private(set) var url: URL
    private(set) var lines: [PgpassLine] = []
    private(set) var mode: Int?
    private(set) var lastSaved: Date?
    /// The file changed on disk while there were unsaved changes here.
    private(set) var changedOnDisk = false
    var errorMessage: String?
    /// A short message that clears itself, such as "reloaded from disk".
    var notice: String?

    /// The lines as last read from or written to disk.
    private var savedLines: [PgpassLine] = []
    private var loadedModificationDate: Date?

    /// The window's undo manager, so ⌘Z and ⇧⌘Z work. ContentView sets it.
    @ObservationIgnored weak var undoManager: UndoManager?
    @ObservationIgnored private var dragSnapshot: [PgpassLine]?
    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var pendingDiskCheck: DispatchWorkItem?
    @ObservationIgnored private var noticeTimer: DispatchWorkItem?

    init(url: URL = PgpassFile.defaultLocation()) {
        self.url = url
        reload()
        watcher = FileWatcher(url: url) { [weak self] in
            MainActor.assumeIsolated { self?.fileChangedOnDisk() }
        }
    }

    // MARK: Derived state

    var isDirty: Bool { lines != savedLines }

    var fileExists: Bool { FileManager.default.fileExists(atPath: url.path) }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    var modeString: String { mode.map(PgpassFile.formatMode) ?? "unknown" }

    var permissionsTooOpen: Bool { mode.map(PgpassFile.isTooOpen) ?? false }

    var entryLines: [PgpassLine] { lines.filter { $0.entry != nil } }

    var entries: [PgpassEntry] { lines.compactMap(\.entry) }

    var hosts: [String] {
        var seen = Set<String>()
        return entries.map(\.host).filter { seen.insert($0).inserted }
    }

    /// Shadowed line ID -> ID of the earlier line that hides it.
    var shadowMap: [PgpassLine.ID: PgpassLine.ID] {
        let lines = entryLines
        var map: [PgpassLine.ID: PgpassLine.ID] = [:]
        for (i, by) in PgpassMatcher.shadowing(lines.compactMap(\.entry)).enumerated() {
            if let by { map[lines[i].id] = lines[by].id }
        }
        return map
    }

    /// What "Fix order" would do to the current lines.
    var orderFix: OrderFix { PgpassOrderFixer.fix(lines) }

    func line(_ id: PgpassLine.ID) -> PgpassLine? {
        lines.first { $0.id == id }
    }

    /// 1-based position among entries (comments and blanks don't count).
    func entryNumber(for id: PgpassLine.ID) -> Int? {
        entryLines.firstIndex { $0.id == id }.map { $0 + 1 }
    }

    // MARK: File

    func reload() {
        do {
            lines = try PgpassFile.read(at: url)
            savedLines = lines
            mode = PgpassFile.posixMode(at: url)
            loadedModificationDate = PgpassFile.modificationDate(at: url)
            changedOnDisk = false
            errorMessage = nil
            // Undo steps refer to lines that no longer exist.
            undoManager?.removeAllActions(withTarget: self)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves unless the file changed on disk since it was read; pass
    /// `overwrite: true` to save anyway.
    func save(overwrite: Bool = false) {
        endDrag()
        if !overwrite, fileExists, PgpassFile.modificationDate(at: url) != loadedModificationDate {
            changedOnDisk = true
            return
        }
        do {
            try PgpassFile.write(lines, to: url)
            savedLines = lines
            mode = PgpassFile.posixMode(at: url)
            loadedModificationDate = PgpassFile.modificationDate(at: url)
            changedOnDisk = false
            lastSaved = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fixPermissions() {
        do {
            try PgpassFile.fixPermissions(at: url)
            mode = PgpassFile.posixMode(at: url)
            loadedModificationDate = PgpassFile.modificationDate(at: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func showNotice(_ text: String) {
        notice = text
        noticeTimer?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                if self?.notice == text { self?.notice = nil }
            }
        }
        noticeTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
    }

    // MARK: Changes made outside the app

    /// Called by the watcher. Waits a moment, because editors often write a
    /// file in several steps.
    private func fileChangedOnDisk() {
        pendingDiskCheck?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.checkDisk() }
        }
        pendingDiskCheck = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func checkDisk() {
        mode = PgpassFile.posixMode(at: url)
        // Our own save, or only the permissions changed.
        guard PgpassFile.modificationDate(at: url) != loadedModificationDate else { return }

        if isDirty {
            // Don't throw away edits. The banner offers Reload or Overwrite.
            changedOnDisk = true
            return
        }
        let existed = !lines.isEmpty || loadedModificationDate != nil
        reload()
        if fileExists {
            showNotice("\(displayPath) changed outside pgpmana, so it was reloaded.")
        } else if existed {
            showNotice("\(displayPath) was deleted outside pgpmana.")
        }
    }

    // MARK: Undo

    /// Applies `body` to the lines and registers one undo step for it.
    private func change(_ actionName: String, _ body: (inout [PgpassLine]) -> Void) {
        // A drag dropped outside the list never calls endDrag. File its step now.
        endDrag()
        let before = lines
        body(&lines)
        guard lines != before else { return }
        registerUndo(actionName, restoring: before)
    }

    /// Undoing puts `snapshot` back and registers the opposite step, which
    /// UndoManager files under Redo.
    private func registerUndo(_ actionName: String, restoring snapshot: [PgpassLine]) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated {
                let current = store.lines
                store.lines = snapshot
                store.registerUndo(actionName, restoring: current)
            }
        }
        undoManager.setActionName(actionName)
    }

    // MARK: Editing

    @discardableResult
    func add(_ entry: PgpassEntry, at position: InsertPosition) -> PgpassLine.ID {
        let line = PgpassLine(kind: .entry(entry))
        change("Add Entry") { $0.insert(line, at: Self.insertionIndex(for: position, in: $0)) }
        return line.id
    }

    func update(_ id: PgpassLine.ID, with entry: PgpassEntry) {
        change("Edit Entry") { lines in
            guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
            lines[i].setKind(.entry(entry))
        }
    }

    @discardableResult
    func duplicate(_ id: PgpassLine.ID) -> PgpassLine.ID? {
        guard let i = lines.firstIndex(where: { $0.id == id }), let entry = lines[i].entry else { return nil }
        let copy = PgpassLine(kind: .entry(entry))
        change("Duplicate Entry") { $0.insert(copy, at: i + 1) }
        return copy.id
    }

    func delete(_ id: PgpassLine.ID) {
        let name = line(id)?.entry != nil ? "Delete Entry" : "Delete Line"
        change(name) { $0.removeAll { $0.id == id } }
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        change("Move Entry") { $0.move(fromOffsets: source, toOffset: destination) }
    }

    func move(_ id: PgpassLine.ID, above target: PgpassLine.ID) {
        change("Move Entry") { lines in
            guard id != target, let from = lines.firstIndex(where: { $0.id == id }) else { return }
            let line = lines.remove(at: from)
            let to = lines.firstIndex { $0.id == target } ?? 0
            lines.insert(line, at: to)
        }
    }

    /// Reorders so no entry is hidden by an earlier one. One undo step.
    func applyOrderFix() {
        let fix = PgpassOrderFixer.fix(lines)
        guard fix.changesOrder else { return }
        change("Fix Order") { $0 = fix.lines }
    }

    /// Deletes entries that repeat an earlier entry's host, port, database
    /// and user. Those can never be used. One undo step.
    func removeDuplicates() {
        let ids = Set(PgpassOrderFixer.fix(lines).duplicates.map(\.lineID))
        guard !ids.isEmpty else { return }
        change("Remove Duplicates") { $0.removeAll { ids.contains($0.id) } }
    }

    // MARK: Drag to reorder

    // A drag fires many small moves. They share one undo step: the snapshot is
    // taken when the drag starts and registered when it's dropped.

    func beginDrag() {
        if dragSnapshot == nil { dragSnapshot = lines }
    }

    /// Puts `id` where `target` is, shifting `target` down when moving up and
    /// up when moving down.
    func moveLive(_ id: PgpassLine.ID, to target: PgpassLine.ID) {
        guard let from = lines.firstIndex(where: { $0.id == id }),
              let to = lines.firstIndex(where: { $0.id == target }),
              from != to else { return }
        lines.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    }

    func endDrag() {
        guard let snapshot = dragSnapshot else { return }
        dragSnapshot = nil
        if lines != snapshot { registerUndo("Move Entry", restoring: snapshot) }
    }

    // MARK: Analysis

    /// What would happen if `candidate` were added at `position`, or put in
    /// place of `replacing` when editing.
    func analyze(_ candidate: PgpassEntry, at position: InsertPosition, replacing id: PgpassLine.ID?) -> CandidateAnalysis {
        var simulated = lines
        let marker = PgpassLine(kind: .entry(candidate))
        if let id, let i = simulated.firstIndex(where: { $0.id == id }) {
            simulated[i] = marker
        } else {
            simulated.insert(marker, at: Self.insertionIndex(for: position, in: simulated))
        }
        let entryLines = simulated.filter { $0.entry != nil }
        let shadowing = PgpassMatcher.shadowing(entryLines.compactMap(\.entry))
        let index = entryLines.firstIndex { $0.id == marker.id } ?? 0
        let hides = shadowing.indices.filter { $0 > index && shadowing[$0] == index }.map { $0 + 1 }
        return CandidateAnalysis(entryNumber: index + 1, shadowedBy: shadowing[index].map { $0 + 1 }, hides: hides)
    }

    static func insertionIndex(for position: InsertPosition, in lines: [PgpassLine]) -> Int {
        switch position {
        case .top: return 0
        case .bottom: return lines.count
        case .before(let id): return lines.firstIndex { $0.id == id } ?? lines.count
        }
    }
}
