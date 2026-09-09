import AppKit

// Renders assets/pomodoro.svg onto a rounded-rect app icon plate at the sizes
// iconutil expects. Keeping this in-tree means the bundle icon stays in sync
// with the shared SVG the Qt build already uses.
let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(Data("usage: make-icon.swift <svg> <iconset-dir>\n".utf8))
    exit(2)
}
let source = URL(fileURLWithPath: arguments[1])
let outputDirectory = URL(fileURLWithPath: arguments[2])

guard let glyph = NSImage(contentsOf: source) else {
    FileHandle.standardError.write(Data("could not read \(source.path)\n".utf8))
    exit(1)
}

func render(_ size: Int) -> Data? {
    let side = CGFloat(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS app icons sit on an inset rounded plate rather than filling the tile.
    let margin = side * 0.06
    let plate = NSRect(x: margin, y: margin, width: side - margin * 2, height: side - margin * 2)
    let radius = plate.width * 0.2237
    let path = NSBezierPath(roundedRect: plate, xRadius: radius, yRadius: radius)
    let gradient = NSGradient(
        starting: NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.22, alpha: 1),
        ending: NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)
    )
    gradient?.draw(in: path, angle: -90)

    let inset = plate.width * 0.19
    let glyphRect = plate.insetBy(dx: inset, dy: inset)
    glyph.draw(in: glyphRect, from: .zero, operation: .sourceOver, fraction: 1.0)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, size: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]

try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
for variant in variants {
    guard let data = render(variant.size) else { exit(1) }
    try? data.write(to: outputDirectory.appendingPathComponent("\(variant.name).png"))
}
