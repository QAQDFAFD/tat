import AppKit
import SwiftUI

/// Design tokens from docs/DESIGN.md §5. Everything else uses system semantic colors.
enum Theme {
    static let accent = dynamic(light: 0x0D9488, dark: 0x2DD4BF)
    static let red = dynamic(light: 0xE5484D, dark: 0xFF6369)
    static let green = dynamic(light: 0x30A46C, dark: 0x3DD68C)
    static let live = dynamic(light: 0xE5484D, dark: 0xFF6369)

    static let padding: CGFloat = 14
    static let rowCorner: CGFloat = 6

    static func trend(_ value: Double, redMeansUp: Bool) -> Color {
        if value == 0 { return .secondary }
        return (value > 0) == redMeansUp ? red : green
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Small section title, e.g. "市场".
struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Square icon button with a hover highlight; label doubles as tooltip and accessibility label.
struct IconButton: View {
    let symbol: String
    let label: String
    let identifier: String
    var isActive = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? Theme.accent : .secondary)
                .frame(width: 26, height: 26)
                .background(RoundedRectangle(cornerRadius: Theme.rowCorner).fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }
}

/// Inline error with a retry button.
struct ErrorLine: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.secondary)
            Button("重试", action: retry)
                .buttonStyle(.link)
                .accessibilityIdentifier("tips.retry")
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
    }
}
