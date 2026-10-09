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

    /// Text colour for a label sitting on `fill`. The palette is the user's
    /// own, so whether white or near-black reads better cannot be assumed; it
    /// is whichever has the higher WCAG contrast in the current appearance.
    static func contrasting(_ fill: Color) -> Color {
        let base = NSColor(fill)
        return Color(nsColor: NSColor(name: nil) { appearance in
            var resolved = base
            appearance.performAsCurrentDrawingAppearance {
                resolved = base.usingColorSpace(.sRGB) ?? base
            }
            let luminance = relativeLuminance(resolved)
            let onWhite = 1.05 / (luminance + 0.05)
            let onDark = (luminance + 0.05) / 0.06
            return onDark > onWhite ? NSColor(white: 0.09, alpha: 0.94) : .white
        })
    }

    private static func relativeLuminance(_ color: NSColor) -> CGFloat {
        func linear(_ channel: CGFloat) -> CGFloat {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.redComponent)
            + 0.7152 * linear(color.greenComponent)
            + 0.0722 * linear(color.blueComponent)
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

    /// The app's own tint for primary actions, switches and focus rings. It
    /// is the focus hue rather than the system accent, so the controls belong
    /// to the same palette as the timer they sit under.
    static let accent = focus

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

    /// A panel on that background, in the floating timer's register: a faint
    /// lift and a hairline rather than a drawn box. `controlBackgroundColor`
    /// is the right answer in light mode — white on grey — but in dark mode it
    /// is *darker* than the window, which sinks a panel instead of raising it.
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.045)
            : .controlBackgroundColor
    })

    static let border = Color(nsColor: .separatorColor)

    /// The edge of a panel. Quieter than a separator: it only has to stop the
    /// panel dissolving into the window, not outline it.
    static let hairline = Color.primary.opacity(0.07)

    /// The well a text field, menu or stepper sits in: sunk below the card in
    /// dark mode, a faint grey on the white card in light mode.
    static let fieldFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 0, alpha: 0.24)
            : NSColor(white: 0, alpha: 0.035)
    })

    static let fieldBorder = Color.primary.opacity(0.12)

    /// Resting fill of a secondary button or a tile inside a card.
    static let controlFill = Color.primary.opacity(0.07)

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

    static let cardCorner: CGFloat = 14
    static let controlCorner: CGFloat = 7
}

/// The small capitalised label a panel is named by — the floating timer's
/// phase label, reused so every panel in the window reads as the same object.
struct SectionLabel: View {
    var text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.7)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

/// A named group of content. The name is a quiet label rather than a heading
/// with a symbol, so the content — the numbers, the chart, the rows — is what
/// the eye lands on.
struct Card<Content: View>: View {
    var title: String?
    var subtitle: String?
    var accessory: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String? = nil,
         subtitle: String? = nil,
         accessory: AnyView? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || accessory != nil {
                HStack(alignment: subtitle == nil ? .center : .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        if let title { SectionLabel(title) }
                        if let subtitle {
                            // Capped so an explanation wraps as a paragraph
                            // instead of running the full width of the panel.
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: 520, alignment: .leading)
                        }
                    }
                    Spacer(minLength: 8)
                    if let accessory { accessory }
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: shape)
        .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

/// A single label / value / detail statistic, as bare text. `.controlSize(.large)`
/// gives the numerals the weight a page leads with; the menu bar popover keeps
/// the regular size.
struct StatTile: View {
    var label: String
    var value: String
    var detail: String
    var tint: Color = .primary

    @Environment(\.controlSize) private var controlSize

    private var large: Bool { controlSize == .large || controlSize == .extraLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 3 : 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(large
                      ? Theme.clockFont(26)
                      : .system(.title2, design: .rounded).weight(.medium).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
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
