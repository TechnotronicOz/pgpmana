import SwiftUI
import AppKit
import CoreText

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// Nabis design system tokens: graphite surfaces, gold as the only accent.
enum Theme {
    // Surfaces, layered graphite -> smoke -> ash; flint for hover and badges.
    static let graphite = Color(hex: 0x1A1A18)
    static let smoke = Color(hex: 0x262624)
    static let ash = Color(hex: 0x323230)
    static let flint = Color(hex: 0x444440)

    // Text on dark.
    static let brightWhite = Color(hex: 0xFAFAF8)
    static let coolWhite = Color(hex: 0xF5F3EE)
    static let softStone = Color(hex: 0xEAE7E0)
    static let silverMist = Color(hex: 0xD8D6D0)
    static let pewter = Color(hex: 0xB2B0AB)
    /// Only on graphite. On smoke or ash it drops below 4.5:1; use pewter there.
    static let stone = Color(hex: 0x8C8A84)

    // Gold.
    static let solar = Color(hex: 0xF2BE52)
    static let amber = Color(hex: 0xE8AA3C)
    static let inkBlack = Color(hex: 0x1A1A18)

    // Strokes.
    static let subtleBorder = Color(hex: 0x45443E)
    static let midBorder = Color(hex: 0x3A3A36)

    enum Weight { case regular, medium, semibold, bold }

    /// Inter. Falls back to the system font if Inter isn't registered.
    static func sans(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .regular: name = "Inter-Regular"
        case .medium: name = "Inter-Medium"
        case .semibold: name = "Inter-SemiBold"
        case .bold: name = "Inter-Bold"
        }
        return .custom(name, fixedSize: size)
    }

    /// Roboto Mono, regular or medium.
    static func mono(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        .custom(weight == .regular ? "RobotoMono-Regular" : "RobotoMono-Medium", fixedSize: size)
    }

    /// Registers the bundled fonts for this process only.
    static func registerFonts() {
        let fonts = AppResources.files(in: "Fonts", withExtension: "ttf")
        guard !fonts.isEmpty else { return }
        CTFontManagerRegisterFontURLs(fonts as CFArray, .process, true, nil)
    }
}

/// Finds bundled resources both in the .app (Contents/Resources/<folder>)
/// and in SwiftPM's resource bundle next to the executable (`swift run`).
enum AppResources {
    private static func candidateFolders(_ folder: String) -> [URL] {
        var dirs: [URL] = []
        if let resources = Bundle.main.resourceURL {
            dirs.append(resources.appendingPathComponent(folder))
        }
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            let bundle = exeDir.appendingPathComponent("pgpmana_pgpmana.bundle")
            dirs.append(bundle.appendingPathComponent(folder))
            dirs.append(bundle.appendingPathComponent("Contents/Resources").appendingPathComponent(folder))
        }
        return dirs
    }

    static func files(in folder: String, withExtension ext: String) -> [URL] {
        let fm = FileManager.default
        for dir in candidateFolders(folder) {
            guard let contents = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            let matches = contents.filter { $0.pathExtension.lowercased() == ext }
            if !matches.isEmpty { return matches }
        }
        return []
    }

    static func image(_ name: String, in folder: String = "Images") -> NSImage? {
        let ext = (name as NSString).pathExtension.lowercased()
        let url = files(in: folder, withExtension: ext).first { $0.lastPathComponent == name }
        return url.flatMap(NSImage.init(contentsOf:))
    }
}

// MARK: - Text

/// Roboto Mono, uppercase, 0.22em tracking.
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.amber

    init(_ text: String, color: Color = Theme.amber) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(Theme.mono(10, .medium))
            .tracking(2.2)
            .foregroundStyle(color)
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    var kind: Kind = .secondary
    var compact = false

    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        PillBody(configuration: configuration, kind: kind, compact: compact)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(Theme.sans(12, kind == .primary ? .semibold : .medium))
                .foregroundStyle(kind == .primary ? Theme.inkBlack : Theme.brightWhite)
                .lineLimit(1)
                .padding(.horizontal, compact ? 12 : 14)
                .frame(height: compact ? 26 : 30)
                .background(Capsule().fill(fill))
                .overlay(Capsule().strokeBorder(stroke, lineWidth: 1))
                .contentShape(Capsule())
                .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
                .onHover { hovering = $0 }
        }

        private var fill: Color {
            switch kind {
            case .primary: return Theme.solar
            case .secondary: return hovering ? Theme.ash : Color.clear
            }
        }

        private var stroke: Color {
            switch kind {
            case .primary: return Color.clear
            case .secondary: return hovering ? Theme.flint : Theme.subtleBorder
            }
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var primaryPill: PillButtonStyle { PillButtonStyle(kind: .primary) }
}

/// 28x28 square icon button with a hairline border.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.silverMist)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.ash : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.subtleBorder))
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .onHover { hovering = $0 }
        }
    }
}

/// A square checkbox filled with solar when on.
struct GoldCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(configuration.isOn ? Theme.solar : Theme.graphite)
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(configuration.isOn ? Theme.solar : Theme.subtleBorder)
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.inkBlack)
                    }
                }
                .frame(width: 16, height: 16)
                configuration.label
                    .font(Theme.sans(12))
                    .foregroundStyle(Theme.pewter)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

// MARK: - Fields and surfaces

struct ThemedFieldModifier: ViewModifier {
    var mono = false
    var disabled = false

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(mono ? Theme.mono(13) : Theme.sans(13))
            .foregroundStyle(disabled ? Theme.pewter : Theme.brightWhite)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(disabled ? Theme.ash : Theme.graphite))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.subtleBorder))
    }
}

extension View {
    func themedField(mono: Bool = false, disabled: Bool = false) -> some View {
        modifier(ThemedFieldModifier(mono: mono, disabled: disabled))
    }

    /// 1px divider along one edge.
    func hairline(_ edge: VerticalEdge, color: Color = Theme.subtleBorder) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            Rectangle().fill(color).frame(height: 1)
        }
    }
}

/// Monospaced line preview on graphite.
struct CodeBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(11))
            .foregroundStyle(Theme.softStone)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.graphite))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.midBorder))
    }
}

/// Ash callout with a solar heading.
struct NoticeCard<Actions: View>: View {
    let title: String
    let message: String
    let actions: Actions

    init(title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(Theme.sans(13, .semibold))
                .foregroundStyle(Theme.solar)
            Text(message)
                .font(Theme.sans(13))
                .foregroundStyle(Theme.silverMist)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            actions
                .padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.ash))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.subtleBorder))
    }
}

extension NoticeCard where Actions == EmptyView {
    init(title: String, message: String) {
        self.init(title: title, message: message) { EmptyView() }
    }
}

struct NeverUsedBadge: View {
    var body: some View {
        Text("NEVER USED")
            .font(Theme.sans(10, .semibold))
            .foregroundStyle(Theme.solar)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.flint))
            .help("An earlier entry matches every connection this one would.")
    }
}

struct ModeChip: View {
    let mode: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.system(size: 10, weight: .semibold))
            Text("MODE \(mode)")
                .font(Theme.mono(11, .medium))
                .tracking(0.9)
        }
        .foregroundStyle(Theme.softStone)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 4).fill(Theme.flint))
        .help("Only you can read or write this file.")
    }
}

/// Six-dot drag handle.
struct GripDots: View {
    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow {
                    Circle().frame(width: 2.5, height: 2.5)
                    Circle().frame(width: 2.5, height: 2.5)
                }
            }
        }
        .foregroundStyle(Theme.stone)
        .accessibilityHidden(true)
    }
}

/// Lays children out left to right, wrapping to new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        let width = proposal.width.map { $0.isFinite ? $0 : widest } ?? widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
