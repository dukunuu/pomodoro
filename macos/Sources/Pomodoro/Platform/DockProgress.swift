import AppKit

/// The Windows build drives the taskbar button's progress indicator. The Mac
/// equivalent is drawing into the Dock tile, so a glance at the Dock shows how
/// far through the phase you are without opening anything.
enum DockProgress {
    private static var tileView: ProgressTileView?

    static func update(progress: Double, active: Bool, color: NSColor) {
        let tile = NSApp.dockTile
        if !active {
            tile.contentView = nil
            tileView = nil
            tile.display()
            return
        }
        let view = tileView ?? {
            let created = ProgressTileView()
            tileView = created
            tile.contentView = created
            return created
        }()
        view.progress = max(0, min(1, progress))
        view.color = color
        tile.display()
    }
}

private final class ProgressTileView: NSView {
    var progress: Double = 0
    var color: NSColor = .systemOrange

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage.draw(in: bounds)

        let height: CGFloat = bounds.height * 0.13
        let inset: CGFloat = bounds.width * 0.1
        let track = NSRect(x: inset, y: inset * 0.6,
                           width: bounds.width - inset * 2, height: height)
        let radius = height / 2

        NSColor.black.withAlphaComponent(0.55)
            .setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        guard progress > 0 else { return }
        let filled = NSRect(x: track.minX, y: track.minY,
                            width: max(height, track.width * progress), height: height)
        color.setFill()
        NSBezierPath(roundedRect: filled, xRadius: radius, yRadius: radius).fill()
    }
}
