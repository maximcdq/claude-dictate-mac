import AppKit

// MARK: - Caret bar: Claude Code /voice's own indicator, next to the text caret
// Claude Code 2.1.292 swaps its cursor cell for a block glyph " ▁▂▃▄▅▆▇█" while recording: level x1.8 capped at 1,
// smoothed w = w*0.7 + x*0.3 every 50 ms, glyph = round(w*8) in 1...8; gray (128,128,128) under level 0.15, else
// hsl(hue 90°/s, s 0.7, l 0.6). Processing pulses 153..185 gray over 2 s. Other apps' carets can't be restyled, so a
// cell-sized transparent panel sits just right of the real one and draws that block.

public final class CaretBar: NSView {
    public enum Mode { case off, live, processing }

    private let meter: LevelSource
    private var smoothed: CGFloat = 0
    private var timer: Timer?
    private var startedAt = Date()
    private(set) public var mode = Mode.off

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
        meter.start()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.step() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func step() {
        if mode == .live { meter.watch() }
        needsDisplay = true
    }

    public func process() {
        guard mode == .live else { return }
        mode = .processing
        startedAt = Date()
        meter.stop()
    }

    public func off() {
        mode = .off
        meter.stop()
        timer?.invalidate()
        timer = nil
    }

    public override func draw(_ dirtyRect: NSRect) {
        let elapsed = CGFloat(Date().timeIntervalSince(startedAt))
        switch mode {
        case .off: return
        case .processing:
            let k = Easing.pulse(elapsed)
            NSColor(srgbRed: (153 + 32 * k) / 255, green: (153 + 32 * k) / 255, blue: (153 + 32 * k) / 255, alpha: 1).setFill()
            bounds.fill()
        case .live:
            smoothed = smoothed * 0.7 + min(meter.level * 1.8, 1) * 0.3
            let eighths = max(1, min((smoothed * 8).rounded(), 8))
            (meter.level < 0.15 ? NSColor(srgbRed: 128 / 255, green: 128 / 255, blue: 128 / 255, alpha: 1) : Palette.hsl(hue: elapsed * 90)).setFill()
            NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height * eighths / 8).fill()
        }
    }
}

// The bar's window. Where the caret is comes from the app (accessibility), through `caretRect`: global top-left
// coordinates, nil when the focused app reports none.
public final class CaretIndicator {
    public let bar: CaretBar
    private let panel: NSPanel
    private let caretRect: () -> CGRect?

    public init(meter: LevelSource, caretRect: @escaping () -> CGRect?) {
        self.caretRect = caretRect
        bar = CaretBar(frame: NSRect(x: 0, y: 0, width: 9, height: 18), meter: meter)
        panel = NSPanel(contentRect: bar.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.canHide = false  // shows with the app hidden too (Hide Others, ⌘H in Settings)
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.animationBehavior = .none
        panel.contentView = bar
    }

    public func show() {
        bar.off()
        follow()
        panel.orderFrontRegardless()
    }

    // a slim bar just past the character cell at the caret (a terminal cell is about half as wide as the line is
    // tall, and a terminal draws its own block cursor over it); without a caret from the app, beside the mouse pointer
    public func follow() {
        let frame: NSRect
        if let caret = caretRect(), let primary = NSScreen.screens.first {
            let h = min(max(caret.height, 12), 40)
            frame = NSRect(x: caret.minX + (h * 0.5).rounded() + 2, y: primary.frame.height - caret.maxY + (caret.height - h) / 2,
                           width: (h * 0.35).rounded(), height: h)
        } else {
            let m = NSEvent.mouseLocation
            frame = NSRect(x: m.x + 12, y: m.y - 22, width: 9, height: 18)
        }
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    public func hide() {
        bar.off()
        panel.orderOut(nil)
    }
}
