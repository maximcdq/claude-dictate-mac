import AppKit
import Metal
import QuartzCore
import SwiftUI

// MARK: - Notch drips: black liquid seeping from the MacBook's notch while recording
// A few small drips hang from the notch's lower edge and lengthen with the voice; a glow in the badge's colors runs
// round the notch and the drips, faint in silence, brighter with the voice. When the text lands, a check (typed) or a
// copy icon (in the clipboard) draws itself in the menu bar beside the notch, then everything fades back.
// It is one signed distance field drawn by a Metal shader on every display refresh (120 Hz on ProMotion): the notch,
// the drips are smooth-unioned, so they merge like liquid, with crisp antialiased edges at any size.
// The notch itself is hardware: the black drawn inside it doesn't show, the drips seem to come out of it.

// How the drips look, from the settings, read every frame so the sliders show live: `drips` off leaves only the
// glow; `length` and `width` scale the drips (1 is the default, small); `count` how many; `blend` 0...1 how much
// they melt into each other and the notch; `glow` 0...1 the glow's strength and reach, 0 none; the result icon
// sits on Liquid Glass (`glass`) and comes out of the notch's left or right side or below it (`result`).
public enum NotchResultPlace: String, CaseIterable, Identifiable {
    case left, right, below

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .left: "Left of the notch"
        case .right: "Right of the notch"
        case .below: "Below the notch"
        }
    }
}

public struct NotchLook {
    public var drips: Bool
    public var length: CGFloat
    public var width: CGFloat
    public var count: Int
    public var blend: CGFloat
    public var glow: CGFloat
    public var glass: Bool
    public var result: NotchResultPlace

    public init(drips: Bool, length: CGFloat, width: CGFloat, count: Int, blend: CGFloat, glow: CGFloat,
                glass: Bool, result: NotchResultPlace) {
        self.drips = drips
        self.length = length
        self.width = width
        self.count = count
        self.blend = blend
        self.glow = glow
        self.glass = glass
        self.result = result
    }
}

final class NotchDrips {
    enum Mode { case off, live, processing, typed, copied, empty }

    static let maxDrips = 9
    static let leave: TimeInterval = 0.45  // the drips draw back into the notch, the glow and the icon fade

    private let meter: LevelSource
    private let look: () -> NotchLook
    var notch = CGRect.zero  // the notch in the view, top-left origin
    private(set) var mode = Mode.off
    private var smoothed: CGFloat = 0
    private var flow: CGFloat = 0  // the drips' own clock: runs faster with the voice
    private var reach: CGFloat = 0  // how far out the drips are, eased: 0 tucked in the notch, 1 out
    private var shine: CGFloat = 0  // the glow with the voice, eased so the mic's ups and downs don't flicker it
    private var lastFrame = Date()
    private var startedAt = Date()  // hue clock
    private var modeAt = Date()
    private var leavingAt: Date?

    init(meter: LevelSource, look: @escaping () -> NotchLook) {
        self.meter = meter
        self.look = look
    }

    func listen() {
        mode = .live
        smoothed = 0
        reach = 0
        shine = 0
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

    // a fixed pseudo-random 0..<1 per drip and key, so every drip keeps its own place, pace and size
    private static func seed(_ i: Int, _ k: Int) -> CGFloat {
        CGFloat(abs(sin(Double(i * 7 + k) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1))
    }

    // The shader's input for this frame, laid out as `NotchShader.source` reads it.
    func uniforms(scale: CGFloat, now: Date) -> [Float] {
        let look = look()
        let dt = CGFloat(min(max(now.timeIntervalSince(lastFrame), 0), 0.1))
        lastFrame = now
        if mode == .live { meter.watch() }
        let level = mode == .live ? meter.level : 0
        let target = min(level * 1.8, 1)
        // per second, so it eases the same at 60 and 120 Hz: swells fast, settles softer
        smoothed += (target - smoothed) * (1 - exp(-dt * (target > smoothed ? 18 : 6)))
        let speech = min(max((level - 0.1) / 0.1, 0), 1)  // Claude's 0.15 threshold, as on the badge
        let since = CGFloat(now.timeIntervalSince(modeAt))
        let leaving = leavingAt.map { Easing.smoothstep(min(CGFloat(now.timeIntervalSince($0) / Self.leave), 1)) } ?? 0

        // out with the recording (further with the voice), half in while the text finishes, in when it's over
        var out: CGFloat
        switch mode {
        case .off: out = 0
        case .live: out = 0.3 + 0.7 * smoothed
        case .processing: out = 0.35
        case .typed, .copied, .empty: out = 0.2
        }
        if !look.drips { out = 0 }
        out *= 1 - leaving
        reach += (out - reach) * (1 - exp(-dt * 8))
        flow += dt * (mode == .live ? 0.6 + 1.2 * smoothed : 0.4)

        // the glow: the badge's color. As the key goes down it flares up at once and settles, as Siri does, to a
        // faint glow that waits for the voice and brightens with it (the mic's first moments of noise hide under the
        // flare). At the end it just dims and fades out; when nothing came it turns soft coral first, as the badge does.
        let hue = Palette.color(at: CGFloat(now.timeIntervalSince(startedAt)))
        var color = hue
        let live = CGFloat(now.timeIntervalSince(startedAt))
        let flare = mode == .live ? (live < 0.12 ? Easing.smoothstep(live / 0.12) : exp(-(live - 0.12) / 0.32)) : 0
        var rest: CGFloat
        switch mode {
        case .off: rest = 0
        case .live: rest = 0.25 + 0.75 * speech * Easing.smoothstep(min(max((live - 0.25) / 0.3, 0), 1))
        case .processing, .typed, .copied: rest = 0.25
        case .empty:
            color = hue.blended(withFraction: Easing.smoothstep(min(since / 0.25, 1)), of: Palette.nothing)!
            rest = 0.8
        }
        shine += (rest - shine) * (1 - exp(-dt * (rest > shine ? 14 : 5)))
        var glow = max(flare, shine)
        glow *= (1 - leaving) * min(look.glow * 1.4, 1)
        let rgb = color.usingColorSpace(.sRGB) ?? color

        var u = [Float](repeating: 0, count: 15 + 5 * Self.maxDrips)
        u[2] = Float(scale)
        (u[3], u[4], u[5], u[6]) = (Float(notch.minX), Float(notch.minY), Float(notch.maxX), Float(notch.maxY))
        (u[7], u[8], u[9]) = (Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent))
        u[10] = Float(glow)
        // how far the glow reaches, in points: further out in the flare
        u[11] = Float((2 + 12 * look.glow) * (1 + 0.6 * flare))
        u[12] = Float(2 + 6 * look.blend)  // the fillet where a drip leaves the notch
        u[13] = Float(0.5 + 9 * look.blend)  // how much neighboring drips melt together

        // spread over the notch's flat middle, each a little off its slot, breathing at its own pace
        let n = look.drips ? min(max(look.count, 1), Self.maxDrips) : 0
        u[14] = Float(n)
        for i in 0..<n {
            let seed = { Self.seed(i, $0) }
            let slot = n == 1 ? 0.5 : 0.2 + 0.6 * CGFloat(i) / CGFloat(n - 1)
            let x = notch.minX + notch.width * (slot + (seed(1) - 0.5) * 0.45 / CGFloat(n))
            let pace = 0.7 + 0.7 * seed(2)
            let wave = 0.5 + 0.3 * sin(flow * pace * 2 + seed(4) * 6.3) + 0.2 * sin(flow * pace * 3.3 + seed(6) * 6.3)
            let length = 22 * look.length * reach * (0.6 + 0.4 * seed(5)) * (0.35 + 0.65 * wave)
            let bulb = 2.4 * look.width * (0.75 + 0.5 * seed(3)) * (0.65 + 0.35 * reach)
            let j = 15 + 5 * i
            u[j] = Float(x)
            u[j + 1] = Float(notch.maxY - 4)  // the neck starts inside the notch
            u[j + 2] = Float(notch.maxY + length - bulb)  // the bulb's center: the tip hangs `length` below
            u[j + 3] = Float(bulb * 0.55)
            u[j + 4] = Float(bulb)
        }
        return u
    }
}

// The shader and the GPU state, built once and shared: the source compiles off the main thread at launch.
final class NotchShader {
    static let shared = NotchShader()

    let device = MTLCreateSystemDefaultDevice()
    let queue: MTLCommandQueue?
    private(set) var pipeline: MTLRenderPipelineState?

    private init() {
        queue = device?.makeCommandQueue()
        device?.makeLibrary(source: Self.source, options: nil) { [weak self] library, _ in
            guard let self, let device = self.device, let library else { return }
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "notchVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "notchFragment")
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
            DispatchQueue.main.async { self.pipeline = pipeline }
        }
    }

    // Distances in points, top-left origin. u: [2] scale, [3...6] notch minX minY maxX maxY, [7...9] glow color,
    // [10] glow strength, [11] glow reach, [12] notch fillet, [13] drip fillet, [14] drip count, [15...] per drip:
    // x, neck y, bulb y, neck radius, bulb radius.
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 position [[position]]; };

    vertex VOut notchVertex(uint id [[vertex_id]]) {
        float2 uv = float2((id << 1) & 2, id & 2);
        VOut out;
        out.position = float4(uv * 2.0 - 1.0, 0.0, 1.0);
        return out;
    }

    static float smin(float a, float b, float k) {
        float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
        return mix(b, a, h) - k * h * (1.0 - h);
    }

    static float roundedBox(float2 p, float2 center, float2 extent, float r) {
        float2 q = abs(p - center) - extent + r;
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    // round ends of radius r1 and r2, h apart along y, straight sides between
    static float unevenCapsule(float2 p, float r1, float r2, float h) {
        h = max(h, abs(r1 - r2) + 0.01);
        p.x = abs(p.x);
        float b = (r1 - r2) / h;
        float a = sqrt(1.0 - b * b);
        float k = dot(p, float2(-b, a));
        if (k < 0.0) return length(p) - r1;
        if (k > a * h) return length(p - float2(0.0, h)) - r2;
        return dot(p, float2(a, b)) - r1;
    }

    fragment float4 notchFragment(VOut in [[stage_in]], constant float *u [[buffer(0)]]) {
        float scale = u[2];
        float2 p = in.position.xy / scale;
        float4 notch = float4(u[3], u[4], u[5], u[6]);

        // the notch, a little inside the real one so the black never shows past it; its top runs off the view
        float2 lo = float2(notch.x + 3.0, -40.0), hi = float2(notch.z - 3.0, notch.w - 0.5);
        float d = roundedBox(p, (lo + hi) * 0.5, (hi - lo) * 0.5, min(9.0, (hi.x - lo.x) * 0.25));

        int count = int(u[14]);
        float drips = 1e5;
        for (int i = 0; i < count; i++) {
            int j = 15 + 5 * i;
            float2 neck = float2(u[j], u[j + 1]);
            drips = smin(drips, unevenCapsule(p - neck, u[j + 3], u[j + 4], u[j + 2] - u[j + 1]), u[13]);
        }
        if (count > 0) d = smin(d, drips, u[12]);

        float fill = clamp(0.5 - d * scale, 0.0, 1.0);
        float glow = u[10] * exp(-max(d, 0.0) / max(u[11], 0.01)) * (1.0 - fill);
        float3 rgb = float3(u[7], u[8], u[9]) * glow;
        return float4(rgb, fill + glow);
    }
    """
}

// Draws the drips into a Metal layer on every refresh of the screen it's on, only while shown.
private final class NotchView: NSView {
    let drips: NotchDrips
    private var link: CADisplayLink?

    init(frame: NSRect, drips: NotchDrips) {
        self.drips = drips
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not from a nib") }

    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = NotchShader.shared.device
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = false
        layer.framebufferOnly = true
        return layer
    }

    private var metal: CAMetalLayer? { layer as? CAMetalLayer }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        resize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        resize()
    }

    private func resize() {
        let scale = window?.backingScaleFactor ?? 2
        metal?.contentsScale = scale
        metal?.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    func start() {
        resize()
        link?.invalidate()
        link = displayLink(target: self, selector: #selector(step))
        link?.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link?.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step() {
        let shader = NotchShader.shared
        guard drips.mode != .off, let metal, let pipeline = shader.pipeline, let queue = shader.queue,
              let drawable = metal.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let uniforms = drips.uniforms(scale: metal.contentsScale, now: Date())
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.setRenderPipelineState(pipeline)
        uniforms.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}

// The result in the menu bar beside the notch: the system's check or clipboard symbol in the menu bar's own color
// (dark on a light menu bar, white on a dark one), on a Liquid Glass capsule or bare. It springs out of the notch's
// side, sharpening out of a blur as the check draws itself, and melts back into a blur.
final class NotchResult: ObservableObject {
    @Published var symbol: String?
    var glass = true
    var place = NotchResultPlace.right
}

private struct NotchResultView: View {
    @ObservedObject var result: NotchResult

    var body: some View {
        // it grows out of the notch: from the side facing it, or down from its top
        let (anchor, offset): (UnitPoint, CGSize) = switch result.place {
        case .left: (.trailing, CGSize(width: 12, height: 0))
        case .right: (.leading, CGSize(width: -12, height: 0))
        case .below: (.top, CGSize(width: 0, height: -12))
        }
        GlassEffectContainer {
            ZStack {
                if let symbol = result.symbol {
                    NotchResultSymbol(name: symbol)
                        .frame(width: NotchIndicator.resultSize.width, height: NotchIndicator.resultSize.height)
                        .glassEffect(result.glass ? .regular : .identity, in: .capsule)
                        .glassEffectTransition(.materialize)
                        .transition(AnyTransition(.blurReplace)
                            .combined(with: .scale(scale: 0.5, anchor: anchor))
                            .combined(with: .offset(offset)))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// drawn on stroke by stroke once it's in (symbols without drawing data just appear)
private struct NotchResultSymbol: View {
    let name: String
    @State private var drawn = false

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.primary)
            .symbolEffect(.drawOff, isActive: !drawn)
            .onAppear { DispatchQueue.main.async { drawn = true } }
    }
}

// The drips' window: borderless, click-through, over the menu bar around the notch. Only screens with a notch
// can show it: the dictation falls back to the badge elsewhere.
public final class NotchIndicator {
    public enum Outcome { case typed, copied, empty }

    static let side: CGFloat = 70  // room beside the notch for the glow and the result
    static let resultSize = CGSize(width: 40, height: 24)  // the glass capsule, within the menu bar's height
    static let below: CGFloat = 110  // room under it for the longest drips
    private let drips: NotchDrips
    private let look: () -> NotchLook
    private let panel: NSPanel
    private var view: NotchView?
    private let result = NotchResult()
    private let resultView: NSHostingView<NotchResultView>
    private var generation = 0  // a show that comes while the previous hide still draws the drips in wins
    // the menu bar's appearance, light or dark with the wallpaper under it (the app's menu bar item knows it)
    public var menuBarAppearance: () -> NSAppearance? = { nil }

    public init(meter: LevelSource, look: @escaping () -> NotchLook) {
        drips = NotchDrips(meter: meter, look: look)
        self.look = look
        resultView = NSHostingView(rootView: NotchResultView(result: result))
        resultView.sizingOptions = []
        _ = NotchShader.shared  // start compiling now, so the first dictation finds it ready
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

    // false when there's no notch to hang from, or the shader isn't ready
    @discardableResult
    public func show(anywhere: Bool = false) -> Bool {
        guard NotchShader.shared.pipeline != nil, let screen = Self.screen(anywhere: anywhere),
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
        generation += 1
        view?.stop()
        let f = screen.frame
        let width = f.width - left.width - right.width
        let height = screen.safeAreaInsets.top
        let frame = NSRect(x: f.minX + left.width - Self.side, y: f.maxY - height - Self.below,
                           width: width + Self.side * 2, height: height + Self.below)
        panel.setFrame(frame, display: false)
        drips.notch = CGRect(x: Self.side, y: 0, width: width, height: height)
        // the views live only while shown; the result sits in the menu bar just right of the notch
        let content = NSView(frame: NSRect(origin: .zero, size: frame.size))
        let view = NotchView(frame: content.bounds, drips: drips)
        self.view = view
        content.addSubview(view)
        result.symbol = nil
        content.addSubview(resultView)
        panel.contentView = content
        drips.listen()
        panel.orderFrontRegardless()
        view.start()
        return true
    }

    public func process() {
        if drips.mode == .live { drips.set(.processing) }
    }

    // the text landed in the field (a check) or in the clipboard (a clipboard) beside the notch, or nothing came
    // (the glow turns soft coral); then the drips draw back in and it all fades
    public func done(_ outcome: Outcome) {
        switch outcome {
        case .typed: drips.set(.typed)
        case .copied: drips.set(.copied)
        case .empty: drips.set(.empty)
        }
        if outcome != .empty {
            let look = look(), notch = drips.notch
            result.glass = look.glass
            result.place = look.result
            // the capsule 16 pt off the notch's side in the menu bar, in the menu bar's colors, or 8 pt under its
            // middle over the windows, in the system's; in a view with room round it for the glass's rim and the spring
            let size = Self.resultSize, w = size.width + 24, h = size.height + 24
            let half = size.width / 2
            switch look.result {
            case .left: resultView.frame = NSRect(x: notch.minX - 16 - half - w / 2, y: Self.below, width: w, height: notch.height)
            case .right: resultView.frame = NSRect(x: notch.maxX + 16 + half - w / 2, y: Self.below, width: w, height: notch.height)
            case .below: resultView.frame = NSRect(x: notch.midX - w / 2, y: Self.below - 8 - size.height / 2 - h / 2, width: w, height: h)
            }
            resultView.appearance = look.result == .below ? nil : menuBarAppearance()
            withAnimation(.spring(duration: 0.55, bounce: 0.3)) { result.symbol = outcome == .typed ? "checkmark" : "doc.on.clipboard" }
        }
        hide(after: outcome == .empty ? 0.7 : outcome == .copied ? 1.2 : 1.0)
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
        withAnimation(.smooth(duration: NotchDrips.leave * 0.8)) { result.symbol = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + NotchDrips.leave) { [weak self] in
            guard let self, self.generation == shown else { return }
            self.view?.stop()
            self.view = nil
            self.drips.off()
            self.panel.orderOut(nil)
            self.panel.contentView = nil
        }
    }
}
