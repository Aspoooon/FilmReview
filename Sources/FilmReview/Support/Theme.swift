import SwiftUI
import AppKit

enum Theme {
    static let background = Color(red: 0.055, green: 0.055, blue: 0.062)
    static let panel = Color(red: 0.085, green: 0.085, blue: 0.095)
    static let panelRaised = Color(red: 0.115, green: 0.115, blue: 0.126)
    static let stage = Color.black
    static let border = Color.white.opacity(0.075)
    static let borderStrong = Color.white.opacity(0.13)
    static let textPrimary = Color(red: 0.94, green: 0.94, blue: 0.955)
    static let textSecondary = Color(red: 0.60, green: 0.60, blue: 0.64)
    static let textTertiary = Color(red: 0.43, green: 0.43, blue: 0.47)
    static let accent = Color(red: 0.88, green: 0.25, blue: 0.25)
    static let accentSoft = Color(red: 0.88, green: 0.25, blue: 0.25).opacity(0.16)
    static let accentBright = Color(red: 0.96, green: 0.35, blue: 0.33)
    static let success = Color(red: 0.27, green: 0.78, blue: 0.45)

    static let monoSmall = Font.system(size: 11, weight: .medium, design: .monospaced)
    static let mono = Font.system(size: 13, weight: .medium, design: .monospaced)
    static let monoLarge = Font.system(size: 15, weight: .semibold, design: .monospaced)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.12) : Color.white.opacity(0.055))
            )
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct IconButton: View {
    let symbol: String
    let help: String
    var size: CGFloat = 15
    var active: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(active ? Theme.accentBright : (disabled ? Theme.textTertiary : Theme.textPrimary))
                .frame(width: 34, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering && !disabled ? Color.white.opacity(0.08) : Color.clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
        .help(help)
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(Theme.textTertiary)
    }
}

struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
    }
}

struct ShortcutHint: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
    }
}

extension View {
    func helpTooltip(_ text: String) -> some View { self.help(text) }
}
