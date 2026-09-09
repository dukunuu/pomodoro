import AppKit
import SwiftUI

/// The always-on-top timer widget. The Qt port disables this on macOS because
/// Qt cannot make a frameless always-visible window that never steals focus;
/// an `NSPanel` with `.nonactivatingPanel` does exactly that, so the native
/// app gets the feature the ported build had to drop.
final class FloatingTimerPanel: NSPanel {
    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 232, height: 96),
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .utilityWindow

        let hosting = NSHostingView(rootView: AnyView(content))
        hosting.wantsLayer = true
        contentView = hosting
        setFrameAutosaveName("PomodoroFloatingTimer")
        if frame.origin == .zero { moveToDefaultPosition() }
    }

    /// A panel must be able to become key or its text and buttons never
    /// respond, but it must never become main and pull focus from the editor
    /// the user is actually working in.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    private func moveToDefaultPosition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 24,
                               y: visible.maxY - frame.height - 24))
    }
}

/// Compact always-visible readout: phase, countdown, progress, and the two
/// controls worth reaching for without opening the dashboard.
struct FloatingTimerView: View {
    @ObservedObject var service: PomodoroService
    var onOpenDashboard: () -> Void
    @State private var hovering = false

    private var accent: Color { Theme.color(for: service.phase) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                Text(service.phaseLabel.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(0.7)
                    .foregroundStyle(Theme.textMuted)
                Spacer(minLength: 4)
                Text(service.statusLabel)
                    .font(.caption2)
                    .foregroundStyle(service.isOvertime ? Theme.urgent : Color.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(service.remainingText)
                    .font(Theme.clockFont(30))
                    .foregroundStyle(service.isOvertime ? Theme.urgent : Color.primary)
                Spacer(minLength: 6)
                if hovering {
                    HStack(spacing: 2) {
                        Button(action: service.toggle) {
                            Image(systemName: service.running ? "pause.fill" : "play.fill")
                        }
                        .help(service.running ? "Pause" : "Start")
                        Button(action: service.skip) {
                            Image(systemName: "forward.end.fill")
                        }
                        .help("Skip phase")
                        Button(action: onOpenDashboard) {
                            Image(systemName: "square.grid.2x2")
                        }
                        .help("Open dashboard")
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .transition(.opacity)
                }
            }

            ProgressBar(value: service.phaseProgress, color: accent,
                        overtime: service.isOvertime, height: 3)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 232, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(accent.opacity(service.running ? 0.5 : 0.18), lineWidth: 1)
        )
        .environment(\.colorScheme, .dark)
        .onHover { value in
            withAnimation(.easeOut(duration: 0.12)) { hovering = value }
        }
        .onTapGesture(count: 2, perform: onOpenDashboard)
        .contextMenu {
            Button(service.running ? "Pause" : "Start", action: service.toggle)
            Button("Skip phase", action: service.skip)
            Button("Reset phase", action: service.reset)
            Divider()
            Button("Open dashboard", action: onOpenDashboard)
        }
    }
}
