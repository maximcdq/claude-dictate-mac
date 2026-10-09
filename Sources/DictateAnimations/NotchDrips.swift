import AppKit
import SwiftUI

// MARK: - Notch drips: black liquid seeping from the MacBook's notch while recording
// A few small drips hang from the notch's lower edge, swell and lengthen with the voice, let a drop go and grow back.
// They are metaballs: soft shapes blurred and cut at half alpha, so the drips, their necks and the notch merge into
// one liquid outline. Under the black runs a glow in the badge's colors, faint in silence, brighter with the voice.
// The notch itself is real hardware: the black drawn inside it doesn't show, the drips seem to come out of it.

// How the drips look, from the settings: `size` scales them (1 is the default, small), `glow` is the glow's
// strength 0...1, `drips` how many hang from the notch.
public struct NotchLook {
    public var size: CGFloat
    public var glow: CGFloat
    public var drips: Int

    public init(size: CGFloat, glow: CGFloat, drips: Int) {
        self.size = size
        self.glow = glow
        self.drips = drips
    }
}

final class NotchDrips {
    enum Mode { case off, live, processing, done, empty }

    private let meter: LevelSource
    private let look: () -> NotchLook  // read every frame, so the settings show live
    var notch = CGRect.zero  // the notch in the view, top-left origin
    private(set) var mode = Mode.off
    private var smoothed: CGFloat = 0
    private var flow: CGFloat = 0  // the drips' own clock: runs faster with the voice
    private var reach: CGFloat = 0  // how far out the drips are, eased: 0 tucked in the notch, 1 out
    private var lastFrame = Date()
    private var startedAt = Date()  // hue clock
    private var modeAt = Date()
    private var leavingAt: Date?
    static let leave: TimeInterval = 0.45  // the drips draw back into the notch

    init(meter: LevelSource, look: @escaping () -> NotchLook) {
        self.meter = meter
        self.look = look
    }

    func listen() {
        mode = .live
        smoothed = 0
        reach = 0
        startedAt = Date()
        modeAt = Date()
        lastFrame = Date()
        leavingAt = nil
        meter.start()
    }

    func set(_ mode: Mode) {
        guard self.mode != .off else { return }
        self.mode = mode
        modeAt = Date()
        meter.stop()
    }

    func leave() {
        leavingAt = Date()
    }

    func off() {
        mode = .off
        meter.stop()
    }

    // one drip's shapes at the drips' clock `t`: a neck from the notch to a drop that lengthens, lets go and falls
    private func drip(_ i: Int, of n: Int, t: CGFloat, length: CGFloat, radius: CGFloat) -> [CGRect] {
        // spread over the notch's flat middle, each a little off its slot, with its own pace and size
        let seed = { (k: Int) in CGFloat(abs(sin(Double(i * 7 + k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)) }
        let slot = n == 1 ? 0.5 : 0.18 + 0.64 * CGFloat(i) / CGFloat(n - 1)
        let x = notch.minX + notch.width * (slot + (seed(1) - 0.5) * 0.5 / CGFloat(n))
        let period = 1.7 + seed(2) * 1.1
        let r = radius * (0.75 + 0.5 * seed(3))
        let u = ((t / period + seed(4)).truncatingRemainder(dividingBy: 1))
        let top = notch.maxY - r  // the stem starts inside the notch, so it merges with it
        var shapes: [CGRect] = []
        let circle = { (y: CGFloat, r: CGFloat) in shapes.append(CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)) }
        let grow: CGFloat = 0.72  // of the cycle: the drip lengthens, then the drop falls
        if u < grow {
            let k = Easing.smoothstep(u / grow)
            let end = notch.maxY + length * (0.25 + 0.75 * k) * (0.55 + 0.45 * seed(5))
            // the neck: circles thinning from the notch down to the drop
            let steps = 5
            for s in 0...steps {
                let f = CGFloat(s) / CGFloat(steps)
                circle(top + (end - top) * f, r * (1 - 0.45 * f))
            }
            circle(end, r * (0.8 + 0.35 * k))
        } else {
            let k = (u - grow) / (1 - grow)
            // the stem draws back up as the drop falls away, shrinking
            let end = notch.maxY + length * (1 - k) * (0.55 + 0.45 * seed(5))
            for s in 0...3 {
                let f = CGFloat(s) / 3
                circle(top + (end - top) * f, r * (1 - 0.45 * f))
            }
            let falling = notch.maxY + length * (0.55 + 0.45 * seed(5)) + length * 0.9 * k * k
            let drop = r * 1.15 * (1 - k)
            if drop > 0.5 { circle(falling, drop) }
        }
        return shapes
    }

    func draw(_ ctx: inout GraphicsContext, size: CGSize, now: Date) {
        guard mode != .off, notch.width > 0 else { return }
        let look = look()
        let dt = CGFloat(min(now.timeIntervalSince(lastFrame), 0.1))
        lastFrame = now
        if mode == .live { meter.watch() }
        let level = mode == .live ? meter.level : 0
        let target = min(level * 1.8, 1)
        smoothed += (target - smoothed) * (target > smoothed ? 0.3 : 0.08)
        let speech = min(max((level - 0.1) / 0.1, 0), 1)  // Claude's 0.15 threshold, as on the badge
        let since = CGFloat(now.timeIntervalSince(modeAt))

        // how far out the drips are: out with the recording (a little more with the voice), in when it's over
        var out: CGFloat = mode == .live ? 0.55 + 0.45 * smoothed : mode == .processing ? 0.5 : 0.35
        if let leavingAt { out *= 1 - min(CGFloat(now.timeIntervalSince(leavingAt) / Self.leave), 1) }
        reach += (out - reach) * min(dt * 6, 1)
        flow += dt * (mode == .live ? 0.55 + 0.9 * smoothed : 0.45)

        // the glow: the badge's color with the voice, a slow pulse while the text finishes, a flash when it lands,
        // soft coral when nothing came
        let hue = Palette.color(at: CGFloat(now.timeIntervalSince(startedAt)))
        var color = hue
        var glow: CGFloat
        switch mode {
        case .off: return
        case .live: glow = 0.18 + 0.82 * speech
        case .processing: glow = 0.2 + 0.4 * Easing.pulse(since, period: 1.2)
        case .done: glow = 0.9 * max(1 - since / 0.6, 0.3)
        case .empty:
            color = hue.blended(withFraction: Easing.smoothstep(min(since / 0.25, 1)), of: Palette.nothing)!
            glow = 0.6
        }
        if let leavingAt { glow *= 1 - min(CGFloat(now.timeIntervalSince(leavingAt) / Self.leave), 1) }
        glow *= look.glow

        let scale = max(look.size, 0.3)
        let length = 20 * scale * reach
        let radius = 3 * scale * (0.6 + 0.4 * reach)
        let shapes = (0..<max(look.drips, 1)).flatMap { drip($0, of: max(look.drips, 1), t: flow, length: length, radius: radius) }
        // the notch's lower edge, a little inside the real one so the black never shows past it; the top runs off
        // the view, so only its bottom corners round
        let body = Path(roundedRect: CGRect(x: notch.minX + 3, y: -20, width: notch.width - 6, height: notch.maxY + 20 - 0.5),
                        cornerRadius: min(9, notch.width / 4))
        let blur = 2.6 * scale

        if glow > 0.01 {
            var layer = ctx
            layer.addFilter(.blur(radius: 5 + 3 * smoothed))
            layer.addFilter(.alphaThreshold(min: 0.5, color: Color(nsColor: color).opacity(Double(min(glow, 1)))))
            layer.addFilter(.blur(radius: blur))
            layer.drawLayer { inner in
                inner.fill(body, with: .color(.white))
                for r in shapes { inner.fill(Path(ellipseIn: r.insetBy(dx: -1.5, dy: -1.5)), with: .color(.white)) }
            }
        }
        var layer = ctx
        layer.addFilter(.alphaThreshold(min: 0.5, color: .black))
        layer.addFilter(.blur(radius: blur))
        layer.drawLayer { inner in
            inner.fill(body, with: .color(.white))
            for r in shapes { inner.fill(Path(ellipseIn: r), with: .color(.white)) }
        }
    }
}

private struct NotchDripsView: View {
    let drips: NotchDrips

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in drips.draw(&ctx, size: size, now: timeline.date) }
        }
    }
}

// The drips' window: borderless, click-through, over the menu bar around the notch. Only screens with a notch
// can show it: the dictation falls back to the badge elsewhere.
public final class NotchIndicator {
    static let side: CGFloat = 40  // room beside the notch for the glow
    static let below: CGFloat = 110  // room under it for the longest drips
    private let drips: NotchDrips
    private let panel: NSPanel
    private var generation = 0  // a show that comes while the previous hide still draws the drips in wins

    public init(meter: LevelSource, look: @escaping () -> NotchLook) {
        drips = NotchDrips(meter: meter, look: look)
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
    }

    // the notch's screen: the one under the pointer, where the user looks (`anywhere`: any screen with a notch)
    public static func screen(anywhere: Bool = false) -> NSScreen? {
        let notched = NSScreen.screens.filter { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
        let m = NSEvent.mouseLocation
        return notched.first { $0.frame.contains(m) } ?? (anywhere ? notched.first : nil)
    }

    // false when there's no notch to hang from
    @discardableResult
    public func show(anywhere: Bool = false) -> Bool {
        guard let screen = Self.screen(anywhere: anywhere),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        generation += 1
        let f = screen.frame
        let width = f.width - left.width - right.width
        let height = screen.safeAreaInsets.top
        panel.setFrame(NSRect(x: f.minX + left.width - Self.side, y: f.maxY - height - Self.below,
                              width: width + Self.side * 2, height: height + Self.below), display: false)
        drips.notch = CGRect(x: Self.side, y: 0, width: width, height: height)
        // the view lives only while shown: its timeline stops with it
        panel.contentView = NSHostingView(rootView: NotchDripsView(drips: drips))
        drips.listen()
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        return true
    }

    public func process() {
        if drips.mode == .live { drips.set(.processing) }
    }

    // the text landed (a flash of the color) or nothing came (soft coral); then the drips draw back in
    public func done(empty: Bool) {
        drips.set(empty ? .empty : .done)
        hide(after: empty ? 0.5 : 0.35)
    }

    private func hide(after delay: TimeInterval) {
        let shown = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.hide()
        }
    }

    public func hide() {
        let shown = generation
        drips.leave()
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchDrips.leave) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.drips.off()
            self.panel.orderOut(nil)
            self.panel.contentView = nil
        }
    }
}
