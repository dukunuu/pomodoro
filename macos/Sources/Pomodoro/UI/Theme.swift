import SwiftUI
import AppKit

/// Ghostty's selected palette, resolved at launch. Low Signal is the fallback.
/// Only the accent hues are read now: surfaces, text and chrome come from
/// AppKit's semantic colors so the app follows the system appearance.
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

    // Terminal roles, named as the theme file names them. These are the dark
    // variants; `adaptive` derives the light-appearance counterpart.
    static let red = color("palette.1", 0xc0807e)
    static let green = color("palette.2", 0x91a58b)
    static let yellow = color("palette.3", 0xb88f76)
    static let blue = color("palette.4", 0x849aaf)
    static let magenta = color("palette.5", 0xa092b4)
    static let cyan = color("palette.6", 0x7fa6a2)
    static let brightRed = color("palette.9", 0xd39893)
    static let brightYellow = color("palette.11", 0xcba68a)
    static let brightBlue = color("palette.12", 0x9bb0c2)

    /// A terminal palette is tuned for a dark background; the same hex on a
    /// white sheet is washed out. This pairs each accent with a deeper, more
    /// saturated version of itself and lets AppKit pick per appearance, so one
    /// Ghostty theme reads correctly in both light and dark mode.
    static func adaptive(_ dark: Color) -> Color {
        let onDark = NSColor(dark)
        let onLight = deepened(onDark)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? onDark : onLight
        })
    }

    private static func deepened(_ color: NSColor) -> NSColor {
        guard let srgb = color.usingColorSpace(.sRGB) else { return color }
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        srgb.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return NSColor(hue: hue,
                       saturation: min(1, saturation * 1.55 + 0.12),
                       brightness: min(brightness, 0.62),
                       alpha: alpha)
    }
}

enum Theme {
    // MARK: - Accents
    //
    // The only colors the app still chooses for itself. Everything a phase is
    // identified by keeps the terminal palette; everything else is AppKit's.

    static let focus = Palette.adaptive(Palette.yellow)
    static let urgent = Palette.adaptive(Palette.brightRed)
    static let shortBreak = Palette.adaptive(Palette.blue)
    static let longBreak = Palette.adaptive(Palette.green)

    static func color(for phase: Phase) -> Color {
        switch phase {
        case .focus: return focus
        case .short: return shortBreak
        case .long: return longBreak
        }
    }

    // MARK: - Semantic surfaces
    //
    // Named for the role rather than the shade, and resolved by AppKit, so
    // every one of these flips with System Settings › Appearance.

    /// The content area behind the cards.
    static let background = Color(nsColor: .windowBackgroundColor)

    /// A raised box on that background. `controlBackgroundColor` is the right
    /// answer in light mode — white on grey — but in dark mode it is *darker*
    /// than the window, which sinks a card instead of raising it. System
    /// Settings lifts its boxes with a white wash instead, so do the same.
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.06)
            : .controlBackgroundColor
    })

    static let border = Color(nsColor: .separatorColor)

    /// Unfilled track behind a bar, dot or heat cell. A translucent label tint
    /// rather than a fixed grey, so it sits correctly on any material.
    static let trackFill = Color.primary.opacity(0.08)

    static let textMuted = Color.secondary
    /// Captions, axis ticks and legends — one step quieter than secondary.
    static let textFaint = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Typography

    /// Numerals that do not jitter as the countdown ticks. SF Rounded is the
    /// face the system's own timers use.
    static func clockFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// SF Mono, for the content that is genuinely monospaced — file paths and
    /// the instruction text the bridges read.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Categorical range for project charts, drawn from the terminal palette
    /// so a pie chart still reads as part of the same theme.
    static let projectColors: [Color] = [
        Palette.adaptive(Palette.yellow), Palette.adaptive(Palette.blue),
        Palette.adaptive(Palette.green), Palette.adaptive(Palette.magenta),
        Palette.adaptive(Palette.cyan), Palette.adaptive(Palette.brightYellow),
        Palette.adaptive(Palette.brightBlue), Palette.adaptive(Palette.red)
    ]

    static let cardCorner: CGFloat = 10
}

/// A titled group of content: a section label in the sidebar's register, then
/// the content in a standard rounded box. This is the shape System Settings
/// and the rest of the system use for grouped controls.
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
        VStack(alignment: .leading, spacing: 7) {
            if title != nil || accessory != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if let accessory { accessory }
                }
                .padding(.horizontal, 3)
            }
            VStack(alignment: .leading, spacing: 10) {
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
}

/// A single label / value / detail statistic.
struct StatTile: View {
    var label: String
    var value: String
    var detail: String
    var accented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(accented ? Theme.focus : Color.primary)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Menu-style row used by the menu bar popover: a full-width accent highlight
/// on hover and an optional shortcut hint, the way a real menu behaves.
struct MenuRow<Trailing: View>: View {
    var title: String
    var systemImage: String
    var shortcut: String?
    @ViewBuilder var trailing: Trailing
    var action: (() -> Void)?

    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

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

    /// A highlighted menu row draws its whole content in white, icon and
    /// shortcut included, exactly as AppKit's menus do.
    private var highlighted: Bool { hovering && isEnabled && action != nil }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 16)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(highlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            Spacer(minLength: 8)
            trailing
            if let shortcut {
                Text(shortcut)
                    .font(.system(size: 12))
                    .foregroundStyle(highlighted ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(highlighted ? Color.accentColor : .clear)
        )
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if isEnabled { action?() } }
    }
}
