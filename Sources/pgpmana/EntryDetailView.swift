import SwiftUI
import AppKit
import PgpassKit

struct EntryDetailView: View {
    @Environment(PgpassStore.self) private var store
    let lineID: PgpassLine.ID
    var onEdit: () -> Void
    var onSelect: (PgpassLine.ID?) -> Void

    @State private var reveal = false
    @State private var copied: String?

    var body: some View {
        if let line = store.line(lineID), let entry = line.entry {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Eyebrow("Entry \(store.entryNumber(for: lineID) ?? 0) of \(store.entries.count)")
                        Text("\(display(entry.username))@\(display(entry.host))")
                            .font(Theme.sans(17, .semibold))
                            .foregroundStyle(Theme.brightWhite)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let shadowingID = store.shadowMap[lineID] {
                        let number = store.entryNumber(for: shadowingID) ?? 0
                        NoticeCard(
                            title: "This entry is never used",
                            message: "Entry \(number) matches every connection this one would, and libpq stops at the first match."
                        ) {
                            Button("Move above entry \(number)") {
                                store.move(lineID, above: shadowingID)
                            }
                            .buttonStyle(PillButtonStyle(kind: .secondary, compact: true))
                        }
                    }

                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                        detailRow("Host", entry.host)
                        detailRow("Port", entry.port)
                        detailRow("Database", entry.database)
                        detailRow("User", entry.username)
                        GridRow {
                            label("Password")
                            HStack(spacing: 8) {
                                Text(reveal ? entry.password : String(repeating: "•", count: 8))
                                    .font(Theme.mono(13))
                                    .foregroundStyle(Theme.brightWhite)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button {
                                    reveal.toggle()
                                } label: {
                                    Image(systemName: reveal ? "eye.slash" : "eye")
                                }
                                .buttonStyle(IconButtonStyle())
                                .help(reveal ? "Hide password" : "Show password")
                                .accessibilityLabel(reveal ? "Hide password" : "Show password")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("Line as written", color: Theme.pewter)
                        CodeBox(text: reveal ? PgpassParser.render(line) : PgpassParser.formatMasked(entry))
                        if entry.password.contains(":") || entry.password.contains("\\") {
                            Text("The password has a colon or backslash, so each one gets a backslash in front in the file.")
                                .font(Theme.sans(12))
                                .foregroundStyle(Theme.pewter)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    FlowLayout(spacing: 8) {
                        Button("Edit", action: onEdit)
                            .buttonStyle(.pill)
                        Button(copied == "password" ? "Copied" : "Copy password") {
                            copy(entry.password, tag: "password")
                        }
                        .buttonStyle(.pill)
                        Button(copied == "psql" ? "Copied" : "Copy psql command") {
                            copy(PsqlCommand.make(for: entry), tag: "psql")
                        }
                        .buttonStyle(.pill)
                        Button("Duplicate") { onSelect(store.duplicate(lineID)) }
                            .buttonStyle(.pill)
                        Button("Delete") {
                            store.delete(lineID)
                            onSelect(nil)
                        }
                        .buttonStyle(.pill)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: lineID) {
                reveal = false
                copied = nil
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        GridRow {
            label(title)
            Text(display(value))
                .font(Theme.sans(13))
                .foregroundStyle(value == "*" ? Theme.pewter : Theme.brightWhite)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(Theme.sans(13))
            .foregroundStyle(Theme.pewter)
            .gridColumnAlignment(.leading)
    }

    private func display(_ value: String) -> String {
        value == "*" ? "any (*)" : value
    }

    private func copy(_ text: String, tag: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = tag
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copied == tag { copied = nil }
        }
    }
}

enum PsqlCommand {
    /// psql 'host=… port=… dbname=… user=…', skipping wildcard fields.
    static func make(for entry: PgpassEntry) -> String {
        let pairs = [("host", entry.host), ("port", entry.port), ("dbname", entry.database), ("user", entry.username)]
            .filter { $0.1 != "*" && !$0.1.isEmpty }
            .map { "\($0.0)=\(conninfoValue($0.1))" }
        return "psql " + shellQuote(pairs.joined(separator: " "))
    }

    /// libpq conninfo: quote with single quotes when the value has spaces,
    /// quotes or backslashes, escaping ' and \ with a backslash.
    static func conninfoValue(_ value: String) -> String {
        guard value.contains(where: { $0 == " " || $0 == "'" || $0 == "\\" }) else { return value }
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        return "'\(escaped)'"
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
