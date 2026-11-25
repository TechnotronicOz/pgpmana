import SwiftUI

// MARK: - Shared tooltip state

/// One tooltip for the whole bar. Buttons report where they are and what
/// they're called; the bar draws the tooltip above itself, pointing at
/// whichever button the pointer is on.
@MainActor
@Observable
final class ActionTooltipState {
    /// The id of the button whose tooltip is showing.
    var hoveredID: String?
    /// Right after a tooltip has shown, moving to another button shows its
    /// tooltip at once, the way macOS toolbars behave.
    var warm = false
    @ObservationIgnored var coolTask: Task<Void, Never>?
}

struct ActionTipInfo {
    let anchor: Anchor<CGRect>
    let label: String
    let keys: String
    let alignment: ActionIconButton.TipAlignment
}

struct ActionTipKey: PreferenceKey {
    static var defaultValue: [String: ActionTipInfo] = [:]
    static func reduce(value: inout [String: ActionTipInfo], nextValue: () -> [String: ActionTipInfo]) {
        value.merge(nextValue()) { $1 }
    }
}

// MARK: - Bar

/// The bar pinned to the bottom of the details tray.
struct InspectorActionBar<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var tooltip = ActionTooltipState()

    var body: some View {
        HStack(spacing: 4) {
            content
        }
        .environment(tooltip)
        .padding(.horizontal, 12)
        .frame(height: 56)
        .frame(maxWidth: .infinity)
        .background(Theme.smoke.opacity(0.96))
        .hairline(.top)
        .overlayPreferenceValue(ActionTipKey.self) { tips in
            GeometryReader { proxy in
                if let id = tooltip.hoveredID, let tip = tips[id] {
                    ActionTooltip(tip: tip, rect: proxy[tip.anchor], barWidth: proxy.size.width)
                        .transition(.opacity)
                }
            }
            .allowsHitTesting(false)
            .animation(.easeOut(duration: 0.12), value: tooltip.hoveredID)
        }
    }
}

/// A thin vertical rule between groups of actions.
struct ActionBarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.subtleBorder)
            .frame(width: 1, height: 20)
            .padding(.horizontal, 6)
            .accessibilityHidden(true)
    }
}

// MARK: - Tooltip

/// Sits just above the bar with a caret pointing down at the button.
private struct ActionTooltip: View {
    let tip: ActionTipInfo
    /// The button's frame in the bar's coordinates.
    let rect: CGRect
    let barWidth: CGFloat

    private let height: CGFloat = 26
    private let gap: CGFloat = 9   // from the bubble's bottom to the bar's top

    var body: some View {
        ZStack(alignment: .topLeading) {
            placedBubble
                .offset(y: -(height + gap))
            Caret()
                .fill(Color(hex: 0x0F0F0E))
                .frame(width: 12, height: 6)
                .position(x: rect.midX, y: -gap + 2)
        }
        .frame(width: barWidth, alignment: .topLeading)
    }

    /// Centered over the button, or lined up with its outer edge for the
    /// first and last buttons so the bubble stays inside the tray.
    @ViewBuilder
    private var placedBubble: some View {
        switch tip.alignment {
        case .leading:
            bubble
                .padding(.leading, rect.minX)
                .frame(width: barWidth, alignment: .leading)
        case .trailing:
            bubble
                .padding(.trailing, max(0, barWidth - rect.maxX))
                .frame(width: barWidth, alignment: .trailing)
        case .center:
            // A frame twice as wide as the button's center puts the bubble's
            // center on the button's center.
            bubble
                .frame(width: max(1, rect.midX * 2))
        }
    }

    private var bubble: some View {
        HStack(spacing: 8) {
            Text(tip.label)
                .font(Theme.sans(12))
                .foregroundStyle(Theme.brightWhite)
            if !tip.keys.isEmpty {
                Text(tip.keys)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.pewter)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: height)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x0F0F0E)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.subtleBorder))
        .shadow(color: .black.opacity(0.4), radius: 9, y: 4)
        .fixedSize()
    }
}

private struct Caret: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Button

struct ActionIconButton: View {
    enum TipAlignment { case leading, center, trailing }

    @Environment(ActionTooltipState.self) private var tooltip

    let systemImage: String
    let label: String
    /// Shown in the tooltip, for example "⇧⌘C". Empty for none.
    var keys: String = ""
    var shortcut: KeyboardShortcut?
    var danger = false
    /// Swaps the icon for a gold checkmark, for example after copying.
    var confirmed = false
    var tipAlignment: TipAlignment = .center
    let action: () -> Void

    @State private var hovering = false
    @State private var showTask: Task<Void, Never>?

    /// Unique within the bar, and stable while the label changes.
    private var id: String { systemImage }

    var body: some View {
        Button(action: action) {
            Image(systemName: confirmed ? "checkmark" : systemImage)
                .font(.system(size: 14, weight: .medium))
                .contentTransition(.symbolEffect(.replace))
                .foregroundStyle(iconColor)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Theme.ash : Color.clear))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut)
        .accessibilityLabel(label)
        .accessibilityHint(keys.isEmpty ? "" : "Shortcut \(keys)")
        .anchorPreference(key: ActionTipKey.self, value: .bounds) { anchor in
            [id: ActionTipInfo(anchor: anchor, label: label, keys: keys, alignment: tipAlignment)]
        }
        .onHover(perform: hover)
        .onDisappear {
            showTask?.cancel()
            if tooltip.hoveredID == id { tooltip.hoveredID = nil }
        }
    }

    private var iconColor: Color {
        if confirmed { return Theme.solar }
        if hovering { return danger ? Theme.solar : Theme.brightWhite }
        return Theme.silverMist
    }

    private func hover(_ inside: Bool) {
        hovering = inside
        showTask?.cancel()
        tooltip.coolTask?.cancel()
        if inside {
            if tooltip.warm {
                tooltip.hoveredID = id
            } else {
                showTask = Task {
                    try? await Task.sleep(for: .milliseconds(320))
                    guard !Task.isCancelled else { return }
                    tooltip.hoveredID = id
                    tooltip.warm = true
                }
            }
        } else {
            if tooltip.hoveredID == id { tooltip.hoveredID = nil }
            // Stay warm briefly so the next button's tooltip shows at once.
            let state = tooltip
            state.coolTask = Task {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                state.warm = false
            }
        }
    }
}
