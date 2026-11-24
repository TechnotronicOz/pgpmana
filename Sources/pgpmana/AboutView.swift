import SwiftUI
import AppKit

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private static let authorName = "Matt Carter"
    private static let authorEmail = "carter.matt@icloud.com"

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String else {
            return "Development build"
        }
        let build = info?["CFBundleVersion"] as? String
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if let logo = AppResources.image("AppLogo.png") {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                }
            }
            .frame(width: 168, height: 168)
            .accessibilityLabel("pgpmana logo: a faceted blue elephant with its trunk raised")

            VStack(spacing: 6) {
                Text("PGPMANA")
                    .font(Theme.sans(28, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Theme.brightWhite)
                Eyebrow("pgpass manager for Mac", color: Theme.pewter)
                Text(versionText)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.pewter)
                    .padding(.top, 2)
            }
            .padding(.top, 4)

            Rectangle()
                .fill(Theme.subtleBorder)
                .frame(width: 220, height: 1)
                .padding(.vertical, 20)

            VStack(spacing: 6) {
                Eyebrow("Created by")
                Text(Self.authorName)
                    .font(Theme.sans(16, .semibold))
                    .foregroundStyle(Theme.coolWhite)
                Link(Self.authorEmail, destination: URL(string: "mailto:\(Self.authorEmail)")!)
                    .font(Theme.sans(13))
                    .foregroundStyle(Theme.amber)
                    .tint(Theme.amber)
                    .onHover { inside in
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
            }

            Button("Close") { dismiss() }
                .buttonStyle(.primaryPill)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 26)
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, 28)
        .frame(width: 380)
        .background(Theme.smoke)
        .presentationBackground(Theme.smoke)
    }
}
