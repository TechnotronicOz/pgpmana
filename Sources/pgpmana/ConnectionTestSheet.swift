import SwiftUI
import PgpassKit

/// Tries an entry against the real server with psql (or pg_isready).
/// Wildcard fields have to be filled in with a real value first.
struct ConnectionTestSheet: View {
    @Environment(\.dismiss) private var dismiss
    let entry: PgpassEntry

    @State private var host = ""
    @State private var port = ""
    @State private var database = ""
    @State private var username = ""
    @State private var tools: PostgresTools?
    @State private var running = false
    @State private var outcome: ConnectionOutcome?

    private var hasWildcards: Bool { entry.usesWildcard }

    private var target: ConnectionTarget? {
        let values = [host, port, database, username].map { $0.trimmingCharacters(in: .whitespaces) }
        guard values.allSatisfy({ !$0.isEmpty && $0 != "*" }) else { return nil }
        return ConnectionTarget(host: values[0], port: values[1], database: values[2], username: values[3], password: entry.password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow("Test connection")
                Text("\(display(entry.username))@\(display(entry.host))")
                    .font(Theme.sans(20, .semibold))
                    .foregroundStyle(Theme.brightWhite)
                if hasWildcards {
                    Text("This entry uses * for some fields. Fill them in with the values you connect with.")
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.pewter)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }

            VStack(spacing: 12) {
                field("Host", text: $host, placeholder: "localhost")
                field("Port", text: $port, placeholder: "5432")
                field("Database", text: $database, placeholder: "postgres")
                field("User", text: $username, placeholder: "postgres")
            }

            toolLine

            if let outcome {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: outcome.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(outcome.ok ? Theme.solar : Theme.amber)
                        Text(outcome.title)
                            .font(Theme.sans(14, .semibold))
                            .foregroundStyle(Theme.brightWhite)
                    }
                    Text(outcome.detail)
                        .font(Theme.sans(13))
                        .foregroundStyle(Theme.silverMist)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if !outcome.command.isEmpty {
                        CodeBox(text: outcome.command)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.ash))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.subtleBorder))
            }

            HStack(spacing: 10) {
                if running {
                    ProgressView().controlSize(.small)
                    Text("Connecting…")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.pewter)
                }
                Spacer()
                Button("Close", role: .cancel) { dismiss() }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.cancelAction)
                Button("Test", action: runTest)
                    .buttonStyle(.primaryPill)
                    .keyboardShortcut(.defaultAction)
                    .disabled(running || target == nil || tools?.isEmpty != false)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(Theme.smoke)
        .presentationBackground(Theme.smoke)
        .onAppear {
            host = entry.host == "*" ? "" : entry.host
            port = entry.port == "*" ? "" : entry.port
            database = entry.database == "*" ? "" : entry.database
            username = entry.username == "*" ? "" : entry.username
        }
        .task {
            tools = await Task.detached { PostgresTools.find() }.value
        }
    }

    @ViewBuilder
    private var toolLine: some View {
        Group {
            if let tools {
                if let psql = tools.psql {
                    Text("Uses \(psql.path) and only this entry's password.")
                } else if let ready = tools.pgIsReady {
                    Text("Uses \(ready.path). pg_isready can't check passwords, so this only shows whether the server is up.")
                } else {
                    Text("Neither psql nor pg_isready was found. Install them with `brew install libpq`.")
                }
            } else {
                Text("Looking for psql…")
            }
        }
        .font(Theme.sans(12))
        .foregroundStyle(Theme.pewter)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func field(_ label: String, text: Binding<String>, placeholder: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.sans(13, .medium))
                .foregroundStyle(Theme.softStone)
                .frame(width: 84, alignment: .leading)
            TextField(label, text: text, prompt: Text(placeholder).foregroundColor(Theme.stone))
                .labelsHidden()
                .themedField(mono: true)
        }
    }

    private func display(_ value: String) -> String {
        value == "*" ? "any" : value
    }

    private func runTest() {
        guard let target, let tools else { return }
        running = true
        outcome = nil
        Task {
            let result = await ConnectionTester.test(target, tools: tools)
            outcome = result
            running = false
        }
    }
}
