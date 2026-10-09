import AppKit

// The badge's colors: with the voice the mic takes a color cycling through sky blue, blue, light blue and light pink
// (Claude's full hue wheel runs through dark violet and magenta, which sit badly on the glass).
enum Palette {
    // nothing came of the dictation: a soft coral, not an alarm red
    static let nothing = NSColor(srgbRed: 1.0, green: 0.5, blue: 0.47, alpha: 1)
    // the text is in: a soft green, as soft as the coral
    static let typed = NSColor(srgbRed: 0.42, green: 0.86, blue: 0.56, alpha: 1)

    private static let stops: [(CGFloat, CGFloat, CGFloat)] = [
        (0.35, 0.78, 0.98),  // sky blue
        (0.29, 0.56, 1.00),  // blue
        (0.56, 0.77, 1.00),  // light blue
        (1.00, 0.62, 0.80),  // light pink
    ]

    // one stop a second, eased between stops, looping
    static func color(at seconds: CGFloat) -> NSColor {
        let n = CGFloat(stops.count)
        let t = (seconds.truncatingRemainder(dividingBy: n) + n).truncatingRemainder(dividingBy: n)
        let i = Int(t), f = (1 - cos((t - CGFloat(i)) * .pi)) / 2
        let a = stops[i], b = stops[(i + 1) % stops.count]
        return NSColor(srgbRed: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f, alpha: 1)
    }

    // Claude Code's hsl(hue, s 0.7, l 0.6)
    static func hsl(hue: CGFloat) -> NSColor {
        let t = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let c: CGFloat = (1 - abs(2 * 0.6 - 1)) * 0.7, x = c * (1 - abs((t / 60).truncatingRemainder(dividingBy: 2) - 1)), m = 0.6 - c / 2
        let (r, g, b): (CGFloat, CGFloat, CGFloat) =
            t < 60 ? (c, x, 0) : t < 120 ? (x, c, 0) : t < 180 ? (0, c, x) : t < 240 ? (0, x, c) : t < 300 ? (x, 0, c) : (c, 0, x)
        return NSColor(srgbRed: r + m, green: g + m, blue: b + m, alpha: 1)
    }
}
