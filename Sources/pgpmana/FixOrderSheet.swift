import SwiftUI
import PgpassKit

/// Shows what "Fix order" will move before it does anything.
struct FixOrderSheet: View {
    @Environment(PgpassStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let fix = store.orderFix

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Fix order")
                Text(fix.changesOrder ? "Reorder so every entry can match" : "Nothing to reorder")
                    .font(Theme.sans(20, .semibold))
                    .foregroundStyle(Theme.brightWhite)
                Text("libpq uses the first entry that matches. Each hidden entry moves directly above the entry that hides it. Comments, blank lines and every other entry stay where they are.")
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.pewter)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            if fix.changesOrder {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("\(fix.moves.count) \(fix.moves.count == 1 ? "move" : "moves")", color: Theme.pewter)
                    VStack(spacing: 0) {
                        ForEach(Array(fix.moves.enumerated()), id: \.offset) { index, move in
                            moveRow(move)
                                .hairline(.bottom, color: index < fix.moves.count - 1 ? Theme.subtleBorder : .clear)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.graphite))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.midBorder))
                }
            }

            if !fix.duplicates.isEmpty {
                NoticeCard(
                    title: fix.duplicates.count == 1 ? "1 exact duplicate" : "\(fix.duplicates.count) exact duplicates",
                    message: duplicateMessage(fix.duplicates)
                ) {
                    Button("Remove duplicates") { store.removeDuplicates() }
                        .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                }
            }

            HStack(spacing: 10) {
                Text("You can undo this with ⌘Z. Nothing is saved until you press ⌘S.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.pewter)
                Spacer()
                Button(fix.changesOrder ? "Cancel" : "Close", role: .cancel) { dismiss() }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.cancelAction)
                if fix.changesOrder {
                    Button("Fix order") {
                        store.applyOrderFix()
                        dismiss()
                    }
                    .buttonStyle(.primaryPill)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: 620)
        .background(Theme.smoke)
        .presentationBackground(Theme.smoke)
    }

    private func moveRow(_ move: OrderFix.Move) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.solar)
            VStack(alignment: .leading, spacing: 3) {
                Text("Entry \(number(move.lineID)) moves above entry \(number(move.aboveLineID))")
                    .font(Theme.sans(13, .medium))
                    .foregroundStyle(Theme.brightWhite)
                Text(fields(move.lineID) + "  above  " + fields(move.aboveLineID))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.pewter)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    /// Entry numbers as they are in the file now, before the fix.
    private func number(_ id: PgpassLine.ID) -> Int {
        store.entryNumber(for: id) ?? 0
    }

    private func fields(_ id: PgpassLine.ID) -> String {
        store.line(id)?.entry.map { $0.matchFields.joined(separator: ":") } ?? "?"
    }

    private func duplicateMessage(_ duplicates: [OrderFix.Duplicate]) -> String {
        let pairs = duplicates.map { "entry \(number($0.lineID)) repeats entry \(number($0.originalID))" }
        return "Reordering can't help these, because they match exactly the same connections: "
            + pairs.joined(separator: ", ")
            + ". The later one is never used. Removing it keeps the earlier one and its password."
    }
}
