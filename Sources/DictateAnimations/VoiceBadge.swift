import AppKit

// MARK: - Recording badge: a Liquid Glass bubble at the mouse pointer
// Carets are reported differently by every app (or not at all: Chrome's address bar), the pointer is always known.
// So the badge rides above-right of the pointer: a glass capsule with a mic that lights up with the voice.
// The level is Claude Code 2.1.292's: sqrt(min(rms16 / 2000, 1)), x1.8 capped at 1, speech from 0.15. Here at 60 fps,
// smoothed to swell fast and settle softer; the mic is black in silence, and with the voice takes the palette's color.

public final class VoiceBadge: NSView {
    public enum Mode { case off, live, processing, typed, copied, empty }

    private let meter: LevelSource
    private var level: CGFloat { meter.level }
    private var heardAt: Date? { meter.heardAt }  // until the first audio the badge spins
    private var smoothed: CGFloat = 0
    private var timer: Timer?
    private var startedAt = Date()  // hue clock, runs on through processing so the color doesn't jump
    private var processingAt = Date()
    private var doneAt = Date()
    private var emptyAt = Date()
    private var shownAt = Date()
    private var leavingAt: Date?  // set while the badge fades out: the content eases down with it
    private(set) public var mode = Mode.off
    static let introMin: TimeInterval = 0.45  // the spin shows at least this long, so the eye finds the badge
    static let introMax: TimeInterval = 1.5  // and at most this long, even if no audio comes
    static let introFade: TimeInterval = 0.3

    init(frame: NSRect, meter: LevelSource) {
        self.meter = meter
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    public func listen() {
        guard mode == .off else { return }
        mode = .live
        smoothed = 0
        startedAt = Date()
        shownAt = Date()
        leavingAt = nil
        meter.start()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func step() {
        if mode == .live { meter.watch() }
        needsDisplay = true
    }

    public func process() {
        guard mode == .live else { return }
        mode = .processing
        processingAt = Date()
        meter.stop()
    }

    // the text landed: in the field (a check) or in the clipboard (a copy icon); the spinner gives way to it before
    // the badge folds away
    public func done(_ outcome: Mode) {
        guard mode == .live || mode == .processing else { return }
        if mode == .live { processingAt = Date() }
        mode = outcome
        doneAt = Date()
        meter.stop()
    }

    // no text came: the spinner runs on and turns soft coral before the badge folds away
    public func empty() {
        guard mode == .live || mode == .processing else { return }
        if mode == .live { processingAt = Date() }
        mode = .empty
        emptyAt = Date()
        meter.stop()
    }

    func leave() {
        leavingAt = Date()
    }

    public func off() {
        mode = .off
        meter.stop()
        timer?.invalidate()
        timer = nil
    }

    // a check mark, drawn from its left tip down and up to the right as `progress` runs 0 → 1
    private func check(_ color: NSColor, progress: CGFloat, scale: CGFloat, center: CGPoint) {
        let points = [CGPoint(x: -5.5, y: 0.5), CGPoint(x: -1.8, y: -3.5), CGPoint(x: 5.5, y: 4.5)]
            .map { CGPoint(x: center.x + $0.x * scale, y: center.y + $0.y * scale) }
        let first = hypot(points[1].x - points[0].x, points[1].y - points[0].y)
        let second = hypot(points[2].x - points[1].x, points[2].y - points[1].y)
        let eased = 1 - pow(1 - progress, 2)
        var left = (first + second) * eased
        let path = NSBezierPath()
        path.move(to: points[0])
        for (from, to, length) in [(points[0], points[1], first), (points[1], points[2], second)] where left > 0 {
            let f = min(left / length, 1)
            path.line(to: CGPoint(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f))
            left -= length
        }
        path.lineWidth = 2.6 * scale
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    private func mic(_ color: NSColor, size: CGFloat, center: CGPoint, symbol: String = "mic.fill") {
        let config = NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        let s = image.size
        image.draw(in: NSRect(x: center.x - s.width / 2, y: center.y - s.height / 2, width: s.width, height: s.height))
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard mode != .off else { return }
        let now = Date()
        let hue = Palette.color(at: CGFloat(now.timeIntervalSince(startedAt)))
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        // a horizontal capsule, like the glass it sits in, inset from its edge
        let outline = bounds.insetBy(dx: 3.5, dy: 3.5)
        let capsule = { NSBezierPath(roundedRect: outline, xRadius: outline.height / 2, yRadius: outline.height / 2) }
        // pop in: ease-out with a touch of overshoot over 0.25 s; on the way out, ease down to 85% with the fade
        var pop = Easing.pop(min(CGFloat(now.timeIntervalSince(shownAt)) / 0.25, 1))
        if let leavingAt {
            let out = min(CGFloat(now.timeIntervalSince(leavingAt)) / BadgeIndicator.fadeOut, 1)
            pop *= 1 - 0.15 * out * out
        }

        // a pulse on the mic and an arc running round the ring: while the mic starts and while the text finishes
        let spinner = { (elapsed: CGFloat, color: NSColor, tint: CGFloat) in
            let gray = 0.3 * Easing.pulse(elapsed)  // pulses up from black, where the live mic rests
            let ring = capsule()
            ring.lineWidth = 0.5
            color.withAlphaComponent(0.3).setStroke()
            ring.stroke()
            // a colored segment running round the capsule, one lap a second
            let perimeter = 2 * (outline.width - outline.height) + .pi * outline.height
            let run = capsule()
            let dash: [CGFloat] = [perimeter * 0.28, perimeter * 0.72]
            run.setLineDash(dash, count: 2, phase: -elapsed * perimeter)
            run.lineWidth = 2
            run.lineCapStyle = .round
            color.setStroke()
            run.stroke()
            let micColor = NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1).blended(withFraction: tint, of: color)!
            self.mic(micColor, size: 14 * pop, center: center)
        }
        let ctx = NSGraphicsContext.current?.cgContext
        let faded = { (alpha: CGFloat, body: () -> Void) in
            guard alpha > 0 else { return }
            guard alpha < 1, let ctx else { return body() }
            ctx.saveGState()
            ctx.setAlpha(alpha)
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            body()
            ctx.endTransparencyLayer()
            ctx.restoreGState()
        }

        switch mode {
        case .off: return
        case .live:
            let target = min(level * 1.8, 1)
            smoothed += (target - smoothed) * (target > smoothed ? 0.45 : 0.18)
            // the spin until the mic is heard (and at least introMin), then a crossfade into the live mic
            var intro: CGFloat = 1
            let heard = heardAt ?? (now.timeIntervalSince(shownAt) > Self.introMax ? shownAt.addingTimeInterval(Self.introMax) : nil)
            if let heardAt = heard {
                let from = max(heardAt, shownAt.addingTimeInterval(Self.introMin))
                intro = 1 - min(max(CGFloat(now.timeIntervalSince(from) / Self.introFade), 0), 1)
            }
            faded(intro) { spinner(CGFloat(now.timeIntervalSince(shownAt)), hue, 0) }
            faded(1 - intro) {
                let speech = min(max((level - 0.1) / 0.1, 0), 1)  // crossfade around Claude's 0.15 threshold
                // the mic and the glow share one color: black in silence, the palette's with the voice
                let color = NSColor.black.blended(withFraction: speech, of: hue)!
                // a soft round glow right around the mic: none in silence, stronger and larger with the voice
                color.withAlphaComponent(0.26 * speech).setFill()
                let glow = outline.height / 2 * (0.5 + 0.42 * smoothed) * pop
                NSBezierPath(ovalIn: NSRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)).fill()
                // a faint hairline of the palette's color in silence that thickens and brightens with the level
                let ring = capsule()
                ring.lineWidth = 0.5 + 2.2 * smoothed
                hue.withAlphaComponent(0.3 + 0.6 * speech).setStroke()
                ring.stroke()
                mic(color, size: 14 * (1 + 0.14 * smoothed) * pop, center: center)
            }
        case .processing:
            spinner(CGFloat(now.timeIntervalSince(processingAt)), hue, 0)
        case .empty:
            // the palette's color eases into coral over a quarter second, the mic takes a soft tint of it
            let eased = Easing.smoothstep(min(CGFloat(now.timeIntervalSince(emptyAt)) / 0.25, 1))
            spinner(CGFloat(now.timeIntervalSince(processingAt)), hue.blended(withFraction: eased, of: Palette.nothing)!, 0.6 * eased)
        case .typed, .copied:
            // the spinner dissolves in 0.2 s; a soft burst of the color spreads from the center once, and the icon
            // springs in (0.3 s, a touch of overshoot): a check drawn stroke by stroke, or the copy icon
            let since = CGFloat(now.timeIntervalSince(doneAt))
            let k = min(since / 0.2, 1)
            faded(1 - k) { spinner(CGFloat(now.timeIntervalSince(processingAt)), hue, 0) }
            faded(k) {
                let b = min(since / 0.45, 1)
                let burst = outline.height / 2 * (0.45 + 0.75 * (1 - pow(1 - b, 3)))
                hue.withAlphaComponent(0.32 * (1 - b)).setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - burst, y: center.y - burst, width: burst * 2, height: burst * 2)).fill()
                let ring = capsule()
                ring.lineWidth = 1.5
                hue.withAlphaComponent(0.6).setStroke()
                ring.stroke()
                let spring = Easing.pop(min(since / 0.3, 1))
                if mode == .copied {
                    mic(hue, size: 13 * spring * pop, center: center, symbol: "doc.on.doc.fill")
                } else {
                    check(hue, progress: min(since / 0.28, 1), scale: spring * pop, center: center)
                }
            }
        }
    }
}

// The badge's window: borderless, click-through, on every Space, following the pointer while it shows.
public final class BadgeIndicator {
    static let fadeIn: TimeInterval = 0.22  // quick in, slower out
    static let fadeOut: TimeInterval = 0.4
    static let size = NSSize(width: 64, height: 36)  // a horizontal capsule
    // room around the glass inside the window: Liquid Glass draws its rim a little past its frame, and a window cut
    // to the capsule clipped that rim into a thin dark edge on light backgrounds
    static let pad: CGFloat = 8
    public let badge: VoiceBadge
    private let panel: NSPanel
    private var mouseMonitor: Any?
    private var generation = 0  // a show that comes while the previous hide still fades out wins

    public init(meter: LevelSource) {
        let frame = NSRect(origin: .zero, size: Self.size)
        badge = VoiceBadge(frame: frame, meter: meter)
        let window = frame.insetBy(dx: -Self.pad, dy: -Self.pad).offsetBy(dx: Self.pad, dy: Self.pad)
        panel = NSPanel(contentRect: window, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // a window shadow rims the glass in black
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        let glass = NSGlassEffectView(frame: frame.offsetBy(dx: Self.pad, dy: Self.pad))
        glass.cornerRadius = Self.size.height / 2
        glass.contentView = badge
        let content = NSView(frame: window)
        content.addSubview(glass)
        panel.contentView = content
    }

    public func show() {
        generation += 1
        stopFollowing()
        badge.off()  // the previous dictation's badge may still be fading out
        follow()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeIn
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        // moved on every pointer event as it arrives (they come faster than the display refreshes), not polled
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]) { [weak self] _ in self?.follow() }
    }

    private func stopFollowing() {
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    // above-right of the pointer's tip, kept on the pointer's screen
    func follow() {
        let m = NSEvent.mouseLocation
        var origin = NSPoint(x: m.x + 12, y: m.y + 6)  // the glass's corner, the window sits `pad` outside it
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(m) }) {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX), f.maxX - Self.size.width)
            origin.y = min(max(origin.y, f.minY), f.maxY - Self.size.height)
        }
        origin.x -= Self.pad
        origin.y -= Self.pad
        if origin != panel.frame.origin { panel.setFrameOrigin(origin) }
    }

    // after a moment on screen, unless a new dictation shows the badge meanwhile
    public func hide(after delay: TimeInterval) {
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.hide()
        }
    }

    public func hide() {
        let shown = generation
        badge.leave()
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = Self.fadeOut
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.generation == shown else { return }
            self.stopFollowing()
            self.badge.off()
            self.panel.orderOut(nil)
        })
    }
}
