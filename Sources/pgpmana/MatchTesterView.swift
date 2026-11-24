import SwiftUI
import PgpassKit

struct MatchTesterView: View {
    @Environment(PgpassStore.self) private var store

    @State private var host = "localhost"
    @State private var port = "5432"
    @State private var database = ""
    @State private var username = "postgres"

    private enum Col {
        static let number: CGFloat = 40
        static let port: CGFloat = 60
        static let database: CGFloat = 150
        static let user: CGFloat = 150
        static let result: CGFloat = 230
    }

    var body: some View {
        let query = ConnectionQuery(host: host, port: port, database: database, username: username)
        let entries = store.entries
        let winner = PgpassMatcher.firstMatch(in: entries, for: query)
        let laterMatches = entries.indices.filter { i in
            guard let winner, i > winner else { return false }
            return PgpassMatcher.matches(entries[i], query)
        }
        let rows = makeRows(entries: entries, query: query, winner: winner)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("Match tester")
                    Text("Which entry will psql use?")
                        .font(Theme.sans(22, .bold))
                        .tracking(-0.22)
                        .foregroundStyle(Theme.brightWhite)
                }

                HStack(alignment: .top, spacing: 16) {
                    input("Host", text: $host, placeholder: "localhost")
                    input("Port", text: $port, placeholder: "5432")
                        .frame(width: 100)
                    input("Database", text: $database, placeholder: "database")
                    input("User", text: $username, placeholder: "user")
                }
                .padding(18)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.smoke))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.midBorder))

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    if let winner {
                        Text("Entry \(winner + 1)")
                            .font(Theme.sans(28, .bold))
                            .tracking(-0.56)
                            .foregroundStyle(Theme.solar)
                        Text("supplies the password." + skippedNote(laterMatches.count))
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.brightWhite)
                    } else {
                        Text("No entry matches")
                            .font(Theme.sans(18, .semibold))
                            .foregroundStyle(Theme.solar)
                        Text("psql will ask for a password, or fail if it can't ask.")
                            .font(Theme.sans(14))
                            .foregroundStyle(Theme.brightWhite)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.ash))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.subtleBorder))

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text("LINE").frame(width: Col.number, alignment: .leading)
                        Text("HOST").frame(maxWidth: .infinity, alignment: .leading)
                        Text("PORT").frame(width: Col.port, alignment: .leading)
                        Text("DATABASE").frame(width: Col.database, alignment: .leading)
                        Text("USER").frame(width: Col.user, alignment: .leading)
                        Text("RESULT").frame(width: Col.result, alignment: .leading)
                    }
                    .font(Theme.mono(10, .medium))
                    .tracking(1.6)
                    .foregroundStyle(Theme.pewter)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.smoke)
                    .hairline(.bottom)

                    ForEach(rows) { row in
                        HStack(spacing: 12) {
                            Text("\(row.number)")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.pewter)
                                .frame(width: Col.number, alignment: .leading)
                            cell(row.entry.host, row.hits[0])
                                .frame(maxWidth: .infinity, alignment: .leading)
                            cell(row.entry.port, row.hits[1])
                                .frame(width: Col.port, alignment: .leading)
                            cell(row.entry.database, row.hits[2])
                                .frame(width: Col.database, alignment: .leading)
                            cell(row.entry.username, row.hits[3])
                                .frame(width: Col.user, alignment: .leading)
                            result(row)
                                .frame(width: Col.result, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(row.status == .used ? Theme.ash : Theme.graphite)
                        .overlay(alignment: .bottom) {
                            if row.number < rows.count {
                                Rectangle().fill(Theme.subtleBorder).frame(height: 1)
                            }
                        }
                    }

                    if rows.isEmpty {
                        Text("No entries in the file yet.")
                            .font(Theme.sans(13))
                            .foregroundStyle(Theme.stone)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.midBorder))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Fields that don't match are struck through. An empty host is matched as localhost.")
                        .foregroundStyle(Theme.stone)
                    if ProcessInfo.processInfo.environment["PGPASSWORD"] != nil {
                        Text("PGPASSWORD is set in pgpmana's environment. When it's set, libpq doesn't read the password file.")
                            .foregroundStyle(Theme.amber)
                    }
                }
                .font(Theme.sans(12))
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .background(Theme.graphite)
        .frame(minWidth: 880, minHeight: 540)
    }

    private func skippedNote(_ count: Int) -> String {
        switch count {
        case 0: return ""
        case 1: return " 1 later entry also matches and is skipped."
        default: return " \(count) later entries also match and are skipped."
        }
    }

    private func input(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(Theme.sans(13, .medium))
                .foregroundStyle(Theme.softStone)
            TextField(label, text: text, prompt: Text(placeholder).foregroundColor(Theme.stone))
                .labelsHidden()
                .themedField(mono: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ value: String, _ hit: Bool) -> some View {
        Text(value)
            .font(Theme.mono(13))
            .strikethrough(!hit, color: Theme.pewter)
            .foregroundStyle(hit ? Theme.brightWhite : Theme.pewter)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    @ViewBuilder
    private func result(_ row: MatchRow) -> some View {
        switch row.status {
        case .used:
            Text(row.result)
                .font(Theme.sans(12, .semibold))
                .foregroundStyle(Theme.inkBlack)
                .padding(.horizontal, 10)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.solar))
        case .skipped:
            Text(row.result)
                .font(Theme.sans(12, .semibold))
                .foregroundStyle(Theme.amber)
        case .noMatch:
            Text(row.result)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.pewter)
        }
    }

    private func makeRows(entries: [PgpassEntry], query: ConnectionQuery, winner: Int?) -> [MatchRow] {
        let labels = ["host", "port", "database", "user"]
        return entries.enumerated().map { i, entry in
            let hits = PgpassMatcher.fieldResults(entry, query)
            let status: MatchRow.Status
            let result: String
            if hits.allSatisfy({ $0 }) {
                status = i == winner ? .used : .skipped
                result = i == winner ? "Used" : "Matches, but entry \((winner ?? 0) + 1) wins"
            } else {
                status = .noMatch
                let missed = zip(labels, hits).filter { !$0.1 }.map(\.0)
                result = missed.joined(separator: ", ") + (missed.count == 1 ? " differs" : " differ")
            }
            return MatchRow(number: i + 1, entry: entry, hits: hits, status: status, result: result)
        }
    }
}

private struct MatchRow: Identifiable {
    enum Status { case used, skipped, noMatch }
    var id: Int { number }
    let number: Int
    let entry: PgpassEntry
    let hits: [Bool]
    let status: Status
    let result: String
}
