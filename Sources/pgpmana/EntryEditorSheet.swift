import SwiftUI
import AppKit
import PgpassKit

struct EntryEditorSheet: View {
    @Environment(PgpassStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let request: EditorRequest
    /// The line selected in the list when the sheet opened.
    let selection: PgpassLine.ID?
    var onSaved: (PgpassLine.ID) -> Void

    @State private var host = "localhost"
    @State private var port = "5432"
    @State private var database = ""
    @State private var username = ""
    @State private var password = ""
    @State private var anyHost = false
    @State private var anyPort = false
    @State private var anyDatabase = false
    @State private var anyUser = false
    @State private var showPassword = false
    @State private var position: InsertPosition = .bottom
    @State private var urlText = ""
    @State private var urlMessage: String?
    @State private var urlFromClipboard = false

    private var editingID: PgpassLine.ID? {
        if case .edit(let id) = request { return id }
        return nil
    }

    private var candidate: PgpassEntry {
        PgpassEntry(
            host: anyHost ? "*" : host,
            port: anyPort ? "*" : port,
            database: anyDatabase ? "*" : database,
            username: anyUser ? "*" : username,
            password: password
        )
    }

    private var validationMessage: String? {
        let c = candidate
        if c.host.isEmpty { return "Enter a host or tick Any." }
        if c.port.isEmpty { return "Enter a port or tick Any." }
        if c.port != "*", !c.port.allSatisfy(\.isNumber) { return "Port must be a number." }
        if c.database.isEmpty { return "Enter a database or tick Any." }
        if c.username.isEmpty { return "Enter a user or tick Any." }
        if c.password.isEmpty { return "Enter a password." }
        return nil
    }

    private var hasEscapes: Bool {
        ([candidate.password] + candidate.matchFields).contains { $0.contains(":") || $0.contains("\\") }
    }

    var body: some View {
        let analysis = store.analyze(candidate, at: position, replacing: editingID)

        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(editingID == nil ? "New entry" : "Edit entry")
                Text(editingID == nil ? "Add a connection" : "Entry \(store.entryNumber(for: editingID!) ?? 0)")
                    .font(Theme.sans(20, .semibold))
                    .foregroundStyle(Theme.brightWhite)
            }

            urlRow

            VStack(spacing: 12) {
                matchField("Host", text: $host, any: $anyHost)
                matchField("Port", text: $port, any: $anyPort, mono: true)
                matchField("Database", text: $database, any: $anyDatabase)
                matchField("User", text: $username, any: $anyUser)
                HStack(spacing: 12) {
                    fieldLabel("Password")
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .labelsHidden()
                    .themedField(mono: showPassword)
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                    }
                    .buttonStyle(IconButtonStyle())
                    .help(showPassword ? "Hide password" : "Show password")
                    .accessibilityLabel(showPassword ? "Hide password" : "Show password")
                    .frame(width: 84, alignment: .leading)
                }
            }

            if editingID == nil {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("Where in the file", color: Theme.pewter)
                    HStack(spacing: 6) {
                        positionPill("Top of file", .top)
                        if let selection, store.line(selection)?.entry != nil {
                            positionPill("Above selected entry", .before(selection))
                        }
                        positionPill("End of file", .bottom)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Eyebrow("Will be written as entry \(analysis.entryNumber)", color: Theme.pewter)
                CodeBox(text: PgpassParser.formatMasked(candidate, bullets: max(password.count, 1)))
                if hasEscapes {
                    Text("Colons and backslashes get a backslash in front, so libpq reads them as part of the value.")
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.pewter)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let by = analysis.shadowedBy {
                NoticeCard(
                    title: "This entry would never be used",
                    message: "Entry \(by) sits above it and matches the same connections. Insert it higher, or narrow entry \(by)."
                )
            } else if !analysis.hides.isEmpty {
                NoticeCard(
                    title: "This entry would hide others",
                    message: "It matches every connection that " + analysis.hides.map { "entry \($0)" }.joined(separator: ", ") + " would, so those stop being used."
                )
            }

            HStack(spacing: 10) {
                if let message = validationMessage {
                    Text(message)
                        .font(Theme.sans(12))
                        .foregroundStyle(Theme.pewter)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.pill)
                    .keyboardShortcut(.cancelAction)
                Button(editingID == nil ? "Add entry" : "Save changes", action: commit)
                    .buttonStyle(.primaryPill)
                    .keyboardShortcut(.defaultAction)
                    .disabled(validationMessage != nil)
            }
        }
        .padding(28)
        .frame(width: 600)
        .background(Theme.smoke)
        .presentationBackground(Theme.smoke)
        .onAppear(perform: load)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .font(Theme.sans(13, .medium))
            .foregroundStyle(Theme.softStone)
            .frame(width: 84, alignment: .leading)
    }

    private func matchField(_ label: String, text: Binding<String>, any: Binding<Bool>, mono: Bool = false) -> some View {
        HStack(spacing: 12) {
            fieldLabel(label)
            TextField(label, text: any.wrappedValue ? .constant("*") : text)
                .labelsHidden()
                .disabled(any.wrappedValue)
                .themedField(mono: mono || any.wrappedValue, disabled: any.wrappedValue)
            Toggle("Any (*)", isOn: any)
                .toggleStyle(GoldCheckboxStyle())
                .frame(width: 84, alignment: .leading)
        }
    }

    private func positionPill(_ title: String, _ value: InsertPosition) -> some View {
        let on = position == value
        return Button {
            position = value
        } label: {
            Text(title)
                .font(Theme.sans(12, on ? .semibold : .regular))
                .foregroundStyle(on ? Theme.brightWhite : Theme.silverMist)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(on ? Theme.flint : Color.clear))
                .overlay(Capsule().strokeBorder(on ? Theme.solar : Theme.subtleBorder))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Paste a postgres:// URL and fill in every field from it.
    private var urlRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow("Fill from a connection URL", color: Theme.pewter)
            HStack(spacing: 8) {
                TextField("Connection URL", text: $urlText, prompt: Text("postgres://user:password@host:5432/database").foregroundColor(Theme.stone))
                    .labelsHidden()
                    .themedField(mono: true)
                    .onSubmit(fillFromURL)
                Button("Fill", action: fillFromURL)
                    .buttonStyle(.pill)
                    .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let urlMessage {
                Text(urlMessage)
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.pewter)
                    .fixedSize(horizontal: false, vertical: true)
            } else if urlFromClipboard {
                Text("Found a connection URL on the clipboard. Press Fill to use it.")
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.pewter)
            }
        }
    }

    private func fillFromURL() {
        do {
            let e = try ConnectionURL.parse(urlText)
            anyHost = false
            anyPort = false
            anyDatabase = false
            anyUser = false
            host = e.host
            port = e.port
            database = e.database
            username = e.username
            password = e.password
            urlText = ""
            urlFromClipboard = false
            urlMessage = "Filled in from the URL. Check the fields, then save."
        } catch {
            urlMessage = error.localizedDescription
        }
    }

    private func load() {
        if editingID == nil,
           let clip = NSPasteboard.general.string(forType: .string),
           ConnectionURL.looksLikeURL(clip) {
            urlText = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            urlFromClipboard = true
        }
        guard let id = editingID, let entry = store.line(id)?.entry else { return }
        anyHost = entry.host == "*"
        anyPort = entry.port == "*"
        anyDatabase = entry.database == "*"
        anyUser = entry.username == "*"
        host = anyHost ? "" : entry.host
        port = anyPort ? "" : entry.port
        database = anyDatabase ? "" : entry.database
        username = anyUser ? "" : entry.username
        password = entry.password
    }

    private func commit() {
        guard validationMessage == nil else { return }
        if let id = editingID {
            store.update(id, with: candidate)
            onSaved(id)
        } else {
            onSaved(store.add(candidate, at: position))
        }
        dismiss()
    }
}
