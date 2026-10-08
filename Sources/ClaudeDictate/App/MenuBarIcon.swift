import AppKit

// The menu bar icon: a microphone inside Claude's spark, the rays standing for the voice going out. A template image
// drawn in code, so it is crisp at any scale and takes the menu bar's color (and the system's highlight) by itself.
enum MenuBarIcon {
    static func image(recording: Bool = false) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            draw(in: rect, recording: recording)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Claude Dictate"
        return image
    }

    // also draws the app icon's mark (scripts/icon)
    static func draw(in rect: NSRect, recording: Bool, color: NSColor = .black) {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let unit = rect.width / 18
        color.set()

        // the spark: eight petals round the mic, wide at the root and tapering out, like Claude's mark
        for i in 0..<8 {
            let angle = CGFloat(i) * .pi / 4 + .pi / 8
            let inner = 6.7 * unit, outer = 8.9 * unit
            let root = CGPoint(x: c.x + cos(angle) * inner, y: c.y + sin(angle) * inner)
            let tip = CGPoint(x: c.x + cos(angle) * outer, y: c.y + sin(angle) * outer)
            let petal = NSBezierPath()
            petal.appendArc(withCenter: root, radius: 0.75 * unit, startAngle: (angle * 180 / .pi) + 90, endAngle: (angle * 180 / .pi) + 270)
            petal.appendArc(withCenter: tip, radius: 0.45 * unit, startAngle: (angle * 180 / .pi) - 90, endAngle: (angle * 180 / .pi) + 90)
            petal.close()
            petal.fill()
        }

        // the mic: a capsule head on a cradle and a short stand
        let head = NSRect(x: c.x - 2.1 * unit, y: c.y - 0.3 * unit, width: 4.2 * unit, height: 5.6 * unit)
        let capsule = NSBezierPath(roundedRect: head, xRadius: head.width / 2, yRadius: head.width / 2)
        if recording { capsule.fill() } else { capsule.lineWidth = 1.3 * unit; capsule.stroke() }
        let cradle = NSBezierPath()
        cradle.appendArc(withCenter: CGPoint(x: c.x, y: c.y + 0.9 * unit), radius: 3.5 * unit, startAngle: 200, endAngle: 340)
        cradle.move(to: CGPoint(x: c.x, y: c.y - 2.6 * unit))
        cradle.line(to: CGPoint(x: c.x, y: c.y - 4.3 * unit))
        cradle.lineWidth = 1.3 * unit
        cradle.lineCapStyle = .round
        cradle.stroke()
    }
}
