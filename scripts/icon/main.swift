// Renders Resources/AppIcon.icns: the menu bar mark (Sources/ClaudeDictate/App/MenuBarIcon.swift) in cream on a
// Claude-coral squircle. Run: scripts/make-icon.sh
import AppKit

let out = CommandLine.arguments[1]  // an .iconset folder

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    // the macOS icon grid: an 824 pt squircle inside the 1024 canvas, a soft shadow under it
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowOffset = NSSize(width: 0, height: -10 * s)
    shadow.shadowBlurRadius = 24 * s
    shadow.set()
    NSColor(srgbRed: 0.85, green: 0.47, blue: 0.34, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.91, green: 0.55, blue: 0.42, alpha: 1),
               ending: NSColor(srgbRed: 0.76, green: 0.37, blue: 0.24, alpha: 1))!.draw(in: shape, angle: -90)
    let mark = tile.insetBy(dx: 130 * s, dy: 130 * s)
    MenuBarIcon.draw(in: mark, recording: true, color: NSColor(srgbRed: 0.99, green: 0.96, blue: 0.92, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for (pt, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
    for scale in scales {
        let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
        try render(pt * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
// the menu bar icon at 2x, light and dark, to look at
for (name, color) in [("menubar-light.png", NSColor.black), ("menubar-dark.png", NSColor.white)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    MenuBarIcon.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36), recording: false, color: color)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/../\(name)"))
}
