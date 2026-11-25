import Foundation

/// The result of reordering a file so no entry is hidden by an earlier one.
public struct OrderFix: Equatable, Sendable {
    public struct Move: Equatable, Sendable {
        /// The entry that moves.
        public let lineID: PgpassLine.ID
        /// It goes directly above this entry, which used to hide it.
        public let aboveLineID: PgpassLine.ID
    }

    public struct Duplicate: Equatable, Sendable {
        /// The later entry, which can never be used.
        public let lineID: PgpassLine.ID
        /// The earlier entry with the same host, port, database and user.
        public let originalID: PgpassLine.ID
    }

    public var lines: [PgpassLine]
    public var moves: [Move]
    /// Entries that repeat an earlier entry's four match fields. Reordering
    /// can't help these: one of each pair has to go.
    public var duplicates: [Duplicate]

    public var changesOrder: Bool { !moves.isEmpty }
}

public enum PgpassOrderFixer {
    /// Moves each hidden entry directly above the entry that hides it, one at
    /// a time, until nothing is hidden. Comments and blank lines stay where
    /// they are, and entries that aren't hidden keep their order.
    ///
    /// Every move takes an entry to an earlier position, so this always ends.
    /// Exact duplicates are reported and left in place.
    public static func fix(_ input: [PgpassLine]) -> OrderFix {
        var lines = input
        var moves: [OrderFix.Move] = []
        var duplicates: [OrderFix.Duplicate] = []
        var skipped = Set<PgpassLine.ID>()

        let limit = max(1, input.count * input.count)
        for _ in 0..<limit {
            let positions = lines.indices.filter { lines[$0].entry != nil }
            let entries = positions.compactMap { lines[$0].entry }
            let shadowing = PgpassMatcher.shadowing(entries)

            guard let k = shadowing.indices.first(where: {
                shadowing[$0] != nil && !skipped.contains(lines[positions[$0]].id)
            }), let byIndex = shadowing[k] else { break }

            let hidden = lines[positions[k]]
            let hider = lines[positions[byIndex]]

            if hidden.entry?.matchFields == hider.entry?.matchFields {
                skipped.insert(hidden.id)
                duplicates.append(OrderFix.Duplicate(lineID: hidden.id, originalID: hider.id))
                continue
            }

            let moved = lines.remove(at: positions[k])
            let target = lines.firstIndex { $0.id == hider.id } ?? 0
            lines.insert(moved, at: target)
            moves.append(OrderFix.Move(lineID: moved.id, aboveLineID: hider.id))
        }

        return OrderFix(lines: lines, moves: moves, duplicates: duplicates)
    }
}
