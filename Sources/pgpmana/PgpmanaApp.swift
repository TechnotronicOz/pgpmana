import SwiftUI
import AppKit

extension Notification.Name {
    static let pgpmanaAddEntry = Notification.Name("pgpmanaAddEntry")
    static let pgpmanaShowAbout = Notification.Name("pgpmanaShowAbout")
}

@main
struct PgpmanaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = PgpassStore()

    init() {
        Theme.registerFonts()
    }

    var body: some Scene {
        Window("pgpmana", id: "main") {
            ContentView()
                .environment(store)
                .frame(minWidth: 1040, minHeight: 600)
                .themed()
                .onAppear { appDelegate.store = store }
        }
        .defaultSize(width: 1200, height: 760)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About pgpmana") {
                    NotificationCenter.default.post(name: .pgpmanaShowAbout, object: nil)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("Add Entry…") {
                    NotificationCenter.default.post(name: .pgpmanaAddEntry, object: nil)
                }
                .keyboardShortcut("n")
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") { store.save() }
                    .keyboardShortcut("s")
                    .disabled(!store.isDirty)
                Button("Revert to Saved") { store.reload() }
                    .keyboardShortcut("r")
            }
        }

        Window("Match Tester", id: "match-tester") {
            MatchTesterView()
                .environment(store)
                .themed()
        }
        .defaultSize(width: 1100, height: 680)
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}

private extension View {
    /// Dark appearance, gold tint and Inter as the default font.
    func themed() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Theme.solar)
            .font(Theme.sans(13))
            .foregroundStyle(Theme.silverMist)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: PgpassStore?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable via `swift run`.
        NSApp.setActivationPolicy(.regular)
        // A bare executable has no Info.plist icon, so set the Dock icon here.
        if Bundle.main.bundleURL.pathExtension != "app", let logo = AppResources.image("AppLogo.png") {
            NSApp.applicationIconImage = logo
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store, store.isDirty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Save changes to \(store.displayPath)?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            store.save()
            return store.isDirty ? .terminateCancel : .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
