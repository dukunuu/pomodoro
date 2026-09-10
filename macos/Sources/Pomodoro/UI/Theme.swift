import SwiftUI
import AppKit

/// Ghostty's selected palette, resolved at launch. Low Signal is the fallback.
/// The app uses the dark variant of paired light/dark terminal themes.
enum Palette {
    static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }

    private static let values = GhosttyPalette.load()
    private static func color(_ key: String, _ fallback: UInt32) -> Color {
        let value = values[key]?.trimmingCharacters(in: CharacterSet(charactersIn: "#")) ?? ""
        return hex(UInt32(value, radix: 16) ?? fallback)
    }

    // Terminal roles, named as the theme file names them.
    static let background = color("background", 0x171c22)
    static let foreground = color("foreground", 0xd9d6cf)
    static let brightForeground = color("palette.15", 0xeee9df)
    static let selection = color("selection-background", 0x35464d)
    static let black = color("palette.0", 0x20262e)
    static let red = color("palette.1", 0xc0807e)
    static let green = color("palette.2", 0x91a58b)
    static let yellow = color("palette.3", 0xb88f76)
    static let blue = color("palette.4", 0x849aaf)
    static let magenta = color("palette.5", 0xa092b4)
    static let cyan = color("palette.6", 0x7fa6a2)
    static let muted = color("palette.8", 0x73808c)
    static let brightRed = color("palette.9", 0xd39893)
    static let brightGreen = color("palette.10", 0xa5b99c)
    static let brightYellow = color("palette.11", 0xcba68a)
    static let brightBlue = color("palette.12", 0x9bb0c2)

    // Surfaces track the selected palette, not the old hardcoded background.
    static let surface = color("palette.0", 0x1c222a)
    static let raised = color("palette.0", 0x20262e)
    static let border = color("selection-background", 0x2b333d)
}

enum Theme {
    static let focus = Palette.yellow
    static let focusBright = Palette.brightYellow
    static let urgent = Palette.brightRed
    static let shortBreak = Palette.blue
    static let longBreak = Palette.green

    static let background = Palette.background
    static let surface = Palette.surface
    static let raised = Palette.raised
    static let border = Palette.border
    static let text = Palette.foreground
    static let textBright = Palette.brightForeground
    static let textMuted = Palette.muted

    static func color(for phase: Phase) -> Color {
        switch phase {
        case .focus: return focus
        case .short: return shortBreak
        case .long: return longBreak
        }
    }

    /// Ghostty runs JetBrains Mono; it is bundled inside that app rather than
    /// installed, so fall back through the usual mono stack.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        for name in ["JetBrainsMono-Regular", "JetBrains Mono", "SFMono-Regular"] {
            if NSFont(name: name, size: size) != nil {
                return .custom(name, size: size).weight(weight)
            }
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    /// Numerals that do not jitter as the countdown ticks.
    static func clockFont(_ size: CGFloat) -> Font {
        mono(size, weight: .medium)
    }

    /// Categorical range for project charts, drawn from the terminal palette
    /// so a pie chart still reads as part of the same theme.
    static let projectColors: [Color] = [
        Palette.yellow, Palette.blue, Palette.green, Palette.magenta,
        Palette.cyan, Palette.brightYellow, Palette.brightBlue, Palette.red
    ]

    static let cardCorner: CGFloat = 10

    /// Applied once at launch; the palette assumes a dark host.
    static func applyAppearance() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }
}

/// A titled card. Flat, bordered, low-contrast — the terminal register.
struct Card<Content: View>: View {
    var title: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil, accessory: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || accessory != nil {
                HStack {
                    if let title {
                        Text(title)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                            .textCase(.uppercase)
                            .kerning(0.9)
                    }
                    Spacer(minLength: 8)
                    if let accessory { accessory }
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }
}

/// A single label / value / detail statistic.
struct StatTile: View {
    var label: String
    var value: String
    var detail: String
    var accented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .kerning(0.8)
            Text(value)
                .font(.system(size: 19, weight: .medium).monospacedDigit())
                .foregroundStyle(accented ? Theme.focusBright : Theme.textBright)
            Text(detail)
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Menu-style row used by the menu bar popover: full-width hover highlight and
/// an optional shortcut hint, the way a real menu behaves.
struct MenuRow<Trailing: View>: View {
    var title: String
    var systemImage: String
    var shortcut: String?
    @ViewBuilder var trailing: Trailing
    var action: (() -> Void)?

    @State private var hovering = false

    init(_ title: String,
         systemImage: String,
         shortcut: String? = nil,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() },
         action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.trailing = trailing()
        self.action = action
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 8)
            trailing
            if let shortcut {
                Text(shortcut)
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.textMuted.opacity(0.7))
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering && action != nil ? Palette.selection.opacity(0.55) : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { action?() }
    }
}
