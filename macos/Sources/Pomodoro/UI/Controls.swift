import SwiftUI
import AppKit

// The app's own controls. AppKit's defaults read as a form; these give every
// button, field and row the same shape, the same palette tint and the same
// hover, press and focus feedback, on every page.

// MARK: - Buttons

struct AppButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, destructive }

    var kind: Kind = .secondary
    var tint: Color = Theme.accent
    /// Square, for a symbol with no title.
    var iconOnly = false

    func makeBody(configuration: Configuration) -> some View {
        AppButtonBody(configuration: configuration, kind: kind, tint: tint, iconOnly: iconOnly)
    }
}

extension ButtonStyle where Self == AppButtonStyle {
    static var primary: AppButtonStyle { AppButtonStyle(kind: .primary) }
    static func primary(tint: Color) -> AppButtonStyle { AppButtonStyle(kind: .primary, tint: tint) }
    static var secondary: AppButtonStyle { AppButtonStyle(kind: .secondary) }
    static var ghost: AppButtonStyle { AppButtonStyle(kind: .ghost) }
    static var destructive: AppButtonStyle { AppButtonStyle(kind: .destructive) }
    static var icon: AppButtonStyle { AppButtonStyle(kind: .ghost, iconOnly: true) }
    static var iconFilled: AppButtonStyle { AppButtonStyle(kind: .secondary, iconOnly: true) }
}

private struct AppButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var kind: AppButtonStyle.Kind
    var tint: Color
    var iconOnly: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    private struct Metrics {
        var font: Font
        var height: CGFloat
        var padding: CGFloat
        var corner: CGFloat
    }

    private var metrics: Metrics {
        switch controlSize {
        case .mini, .small:
            return Metrics(font: .system(size: 11.5, weight: .medium), height: 22, padding: 9, corner: 6)
        case .large, .extraLarge:
            return Metrics(font: .system(size: 13.5, weight: .semibold), height: 34, padding: 16, corner: 9)
        default:
            return Metrics(font: .system(size: 13, weight: .medium), height: 28, padding: 12, corner: Theme.controlCorner)
        }
    }

    private var pressed: Bool { configuration.isPressed }

    private var foreground: Color {
        switch kind {
        case .primary: return Palette.contrasting(tint)
        case .secondary: return .primary
        case .ghost: return .primary.opacity(hovering || pressed ? 1 : 0.72)
        case .destructive: return Theme.urgent
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return tint.opacity(pressed ? 0.82 : 1)
        case .secondary: return .primary.opacity(pressed ? 0.15 : hovering ? 0.11 : 0.07)
        case .ghost: return .primary.opacity(pressed ? 0.12 : hovering ? 0.07 : 0)
        case .destructive: return Theme.urgent.opacity(pressed ? 0.26 : hovering ? 0.2 : 0.13)
        }
    }

    var body: some View {
        let metrics = self.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.corner, style: .continuous)
        configuration.label
            .font(metrics.font)
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, iconOnly ? 0 : metrics.padding)
            .frame(minWidth: iconOnly ? metrics.height : nil, minHeight: metrics.height)
            .background(fill, in: shape)
            .overlay {
                if kind == .primary {
                    shape.fill(Color.white.opacity(hovering && !pressed ? 0.12 : 0))
                } else if kind == .secondary {
                    shape.strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? 1 : 0.42)
            .scaleEffect(pressed ? 0.98 : 1)
            .contentShape(shape)
            .onHover { hovering = $0 && isEnabled }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

// MARK: - Text input

/// The well around a text field or editor: fill, hairline border, and an
/// accent ring while it holds focus. The caller owns the focus state, because
/// several fields also act on focus changes themselves.
struct FieldChrome<Content: View>: View {
    var icon: String?
    var focused: Bool
    var padding = EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9)
    @ViewBuilder var content: Content

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous)
        HStack(spacing: 7) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(focused ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    .frame(width: 16)
            }
            content.textFieldStyle(.plain)
        }
        .padding(padding)
        .frame(minHeight: 28)
        .background(Theme.fieldFill, in: shape)
        .overlay(shape.strokeBorder(focused ? Theme.accent : Theme.fieldBorder,
                                    lineWidth: focused ? 1.5 : 1))
        .background(shape.stroke(Theme.accent.opacity(focused ? 0.22 : 0), lineWidth: 5))
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

/// A single-line field that manages its own focus.
struct InputField: View {
    var label: String
    @Binding var text: String
    var prompt: String?
    var icon: String?
    var secure = false
    var font: Font = .system(size: 13)
    var onSubmit: () -> Void = {}

    @FocusState private var focused: Bool

    var body: some View {
        FieldChrome(icon: icon, focused: focused) {
            Group {
                if secure {
                    SecureField(label, text: $text, prompt: Text(prompt ?? label))
                } else {
                    TextField(label, text: $text, prompt: Text(prompt ?? label))
                }
            }
            .font(font)
            .focused($focused)
            .onSubmit(onSubmit)
        }
    }
}

/// A caption above a field, with an optional hint below it.
struct FieldLabel<Content: View>: View {
    var title: String
    var hint: String?
    @ViewBuilder var content: Content

    init(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.hint = hint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            content
            if let hint {
                Text(hint)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Menus and steppers

/// A pop-up menu drawn as a field, so a choice lines up with the text inputs
/// around it instead of sitting in a system pop-up button.
struct MenuField<Options: View>: View {
    var label: String
    var value: String
    var icon: String?
    @ViewBuilder var options: Options

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous)
        Menu {
            options
        } label: {
            HStack(spacing: 7) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                }
                Text(value)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(Theme.fieldFill, in: shape)
            .overlay(shape.strokeBorder(Theme.fieldBorder, lineWidth: 1))
            .contentShape(shape)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(label)
    }
}

/// Minus, value, plus in one well. Holding a button repeats.
struct StepperField: View {
    var label: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit: String
    var valueWidth: CGFloat = 62

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous)
        HStack(spacing: 0) {
            step("minus", enabled: value > range.lowerBound) { value = max(range.lowerBound, value - 1) }
            (Text("\(value)").font(.system(size: 13, weight: .medium).monospacedDigit())
                + Text(" \(unit)").font(.system(size: 12)).foregroundColor(.secondary))
                .lineLimit(1)
                .frame(width: valueWidth)
                .contentTransition(.numericText())
            step("plus", enabled: value < range.upperBound) { value = min(range.upperBound, value + 1) }
        }
        .frame(height: 28)
        .background(Theme.fieldFill, in: shape)
        .overlay(shape.strokeBorder(Theme.fieldBorder, lineWidth: 1))
        .accessibilityRepresentation {
            Stepper(label, value: $value, in: range)
        }
    }

    private func step(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(StepButtonStyle())
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
    }
}

private struct StepButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        StepButtonBody(configuration: configuration)
    }

    private struct StepButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .background(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.06 : 0))
                .opacity(isEnabled ? 1 : 0.3)
                .onHover { hovering = $0 && isEnabled }
        }
    }
}

/// Previous day, the day itself, next day. The day opens a calendar.
struct DayField: View {
    @Binding var day: Date
    @State private var showingCalendar = false

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter
    }()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous)
        HStack(spacing: 0) {
            arrow("chevron.left", help: "Previous day", by: -1)
            Button { showingCalendar = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(Self.formatter.string(from: day))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                }
                .frame(minWidth: 118, minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(StepButtonStyle())
            .help("Choose a day")
            .popover(isPresented: $showingCalendar, arrowEdge: .bottom) {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding(10)
            }
            arrow("chevron.right", help: "Next day", by: 1)
        }
        .frame(height: 28)
        .background(Theme.fieldFill, in: shape)
        .overlay(shape.strokeBorder(Theme.fieldBorder, lineWidth: 1))
        .clipShape(shape)
    }

    private func arrow(_ symbol: String, help: String, by days: Int) -> some View {
        Button {
            day = Fmt.calendar.date(byAdding: .day, value: days, to: day) ?? day
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 26, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(StepButtonStyle())
        .help(help)
    }
}

// MARK: - Switch

/// An on/off switch in the palette's tint. VoiceOver sees an ordinary toggle.
struct Switch: View {
    var label: String
    @Binding var isOn: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.primary.opacity(0.18)))
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.22), radius: 1, y: 0.5)
                        .padding(2)
                }
                .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isOn)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityRepresentation { Toggle(label, isOn: $isOn) }
    }
}

// MARK: - Rows and labels

/// A symbol on a tinted rounded square: the leading mark of a row.
struct IconBadge: View {
    var systemName: String
    var tint: Color = Theme.accent
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16),
                        in: RoundedRectangle(cornerRadius: size * 0.29, style: .continuous))
    }
}

/// Badge, title and explanation on the left; the control on the right.
struct SettingRow<Control: View>: View {
    var icon: String?
    var tint: Color
    var title: String
    var subtitle: String?
    @ViewBuilder var control: Control

    init(_ title: String,
         subtitle: String? = nil,
         icon: String? = nil,
         tint: Color = Theme.accent,
         @ViewBuilder control: () -> Control) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.tint = tint
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            if let icon { IconBadge(systemName: icon, tint: tint) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

/// A setting that is just a switch.
struct ToggleRow: View {
    var title: String
    var subtitle: String?
    var icon: String?
    var tint: Color = Theme.accent
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title, subtitle: subtitle, icon: icon, tint: tint) {
            Switch(label: title, isOn: $isOn)
        }
    }
}

/// The hairline between rows, inset to clear the icon badge.
struct RowDivider: View {
    var inset: CGFloat = 39

    var body: some View {
        Divider().padding(.leading, inset)
    }
}

/// A short state word on a tinted capsule.
struct StatusPill: View {
    var text: String
    var tint: Color = .secondary
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text)
        }
        .font(.system(size: 10.5, weight: .semibold))
        .foregroundStyle(tint)
        .lineLimit(1)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// A neutral tag, for a name in a set.
struct Chip: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Theme.controlFill, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1))
    }
}

/// An inline message that says what kind of message it is.
struct Notice: View {
    enum Kind { case info, success, error }

    var kind: Kind
    var text: String

    init(_ kind: Kind, _ text: String) {
        self.kind = kind
        self.text = text
    }

    private var tint: Color {
        switch kind {
        case .info: return .secondary
        case .success: return Theme.longBreak
        case .error: return Theme.urgent
        }
    }

    private var symbol: String {
        switch kind {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
            Text(text)
                .font(.caption)
                .foregroundStyle(kind == .info ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(kind == .info ? 0.08 : 0.11), in: shape)
        .overlay(shape.strokeBorder(tint.opacity(0.18), lineWidth: 1))
    }
}

/// The top of a sheet: what it is for, under a badge.
struct SheetHeader: View {
    var symbol: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: symbol, tint: Theme.accent, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A section that folds away. The whole header line is the target.
struct Disclosure<Content: View>: View {
    var title: String
    var detail: String?
    var isExpanded: Binding<Bool>?
    @ViewBuilder var content: Content

    @State private var localExpanded = false
    @State private var hovering = false

    init(_ title: String,
         detail: String? = nil,
         isExpanded: Binding<Bool>? = nil,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.detail = detail
        self.isExpanded = isExpanded
        self.content = content()
    }

    private var expanded: Bool { isExpanded?.wrappedValue ?? localExpanded }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) {
                    if let isExpanded { isExpanded.wrappedValue.toggle() } else { localExpanded.toggle() }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .background(Color.primary.opacity(hovering ? 0.05 : 0),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, -6)
            .onHover { hovering = $0 }
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")

            if expanded {
                VStack(alignment: .leading, spacing: 10) {
                    content
                }
                .padding(.leading, 18)
                .transition(.opacity)
            }
        }
    }
}

/// Lays chips out left to right and wraps them onto further lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, in: width)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(subviews, in: bounds.width)
        for (subview, origin) in zip(subviews, rows.origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                          proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, in width: CGFloat) -> (origins: [CGPoint], width: CGFloat, height: CGFloat) {
        var origins: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (origins, widest, y + rowHeight)
    }
}
