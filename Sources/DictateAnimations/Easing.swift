import CoreGraphics

enum Easing {
    // ease-out with a touch of overshoot, t 0 → 1
    static func pop(_ t: CGFloat) -> CGFloat { 1 + 1.7 * pow(t - 1, 3) + 0.7 * pow(t - 1, 2) }

    static func smoothstep(_ k: CGFloat) -> CGFloat { k * k * (3 - 2 * k) }

    // 0 → 1 → 0 every `period` seconds
    static func pulse(_ seconds: CGFloat, period: CGFloat = 2) -> CGFloat { (sin(seconds * .pi * 2 / period) + 1) / 2 }
}
