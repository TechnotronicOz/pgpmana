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
    private(set) var isDirty = false
    private(set) var lastSaved: Date?
    /// The file changed on disk after we read it.
    private(set) var changedOnDisk = false
    var errorMessage: String?

    private var loadedModificationDate: Date?

    init(url: URL = PgpassFile.defaultLocation()) {
        self.url = url
        reload()
    }

    // MARK: Derived state

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
            mode = PgpassFile.posixMode(at: url)
            loadedModificationDate = PgpassFile.modificationDate(at: url)
            isDirty = false
            changedOnDisk = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves unless the file changed on disk since it was read; pass
    /// `overwrite: true` to save anyway.
    func save(overwrite: Bool = false) {
        if !overwrite, fileExists, PgpassFile.modificationDate(at: url) != loadedModificationDate {
            changedOnDisk = true
            return
        }
        do {
            try PgpassFile.write(lines, to: url)
            mode = PgpassFile.posixMode(at: url)
            loadedModificationDate = PgpassFile.modificationDate(at: url)
            isDirty = false
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

    // MARK: Editing

    @discardableResult
    func add(_ entry: PgpassEntry, at position: InsertPosition) -> PgpassLine.ID {
        let line = PgpassLine(kind: .entry(entry))
        lines.insert(line, at: Self.insertionIndex(for: position, in: lines))
        isDirty = true
        return line.id
    }

    func update(_ id: PgpassLine.ID, with entry: PgpassEntry) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[i].setKind(.entry(entry))
        isDirty = true
    }

    @discardableResult
    func duplicate(_ id: PgpassLine.ID) -> PgpassLine.ID? {
        guard let i = lines.firstIndex(where: { $0.id == id }), let entry = lines[i].entry else { return nil }
        let copy = PgpassLine(kind: .entry(entry))
        lines.insert(copy, at: i + 1)
        isDirty = true
        return copy.id
    }

    func delete(_ id: PgpassLine.ID) {
        lines.removeAll { $0.id == id }
        isDirty = true
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        lines.move(fromOffsets: source, toOffset: destination)
        isDirty = true
    }

    /// Drag reordering: puts `id` where `target` is, shifting `target`
    /// down when moving up and up when moving down.
    func moveLive(_ id: PgpassLine.ID, to target: PgpassLine.ID) {
        guard let from = lines.firstIndex(where: { $0.id == id }),
              let to = lines.firstIndex(where: { $0.id == target }),
              from != to else { return }
        lines.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        isDirty = true
    }

    func move(_ id: PgpassLine.ID, above target: PgpassLine.ID) {
        guard id != target, let from = lines.firstIndex(where: { $0.id == id }) else { return }
        let line = lines.remove(at: from)
        let to = lines.firstIndex { $0.id == target } ?? 0
        lines.insert(line, at: to)
        isDirty = true
    }

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
