// Renders the app icon (an SF Symbol on a gradient squircle) at every size
// macOS wants, into an .iconset folder. build.sh turns that into AppIcon.icns
// with `iconutil`. Usage: swift scripts/make-icon.swift <out.iconset>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let symbolName = "cup.and.saucer.fill"
let top = NSColor(red: 1.00, green: 0.72, blue: 0.30, alpha: 1)   // warm amber
let bottom = NSColor(red: 0.85, green: 0.42, blue: 0.10, alpha: 1) // burnt orange

func render(pixels: Int) -> Data {
    let s = CGFloat(pixels)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: s, height: s)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Apple's macOS icon grid: 824pt squircle inset 100pt on a 1024 canvas.
    let inset = s * 100 / 1024
    let radius = s * 185 / 1024
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSGradient(starting: top, ending: bottom)!.draw(in: squircle, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: s * 0.42, weight: .medium)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)!
        .withSymbolConfiguration(config)!
    let size = symbol.size
    let origin = NSPoint(x: (s - size.width) / 2, y: (s - size.height) / 2)
    symbol.draw(in: NSRect(origin: origin, size: size), from: .zero, operation: .sourceOver, fraction: 1)

    return rep.representation(using: .png, properties: [:])!
}

for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
    try render(pixels: points * scale).write(to: outDir.appendingPathComponent(name))
}
print("wrote \(outDir.path)")
