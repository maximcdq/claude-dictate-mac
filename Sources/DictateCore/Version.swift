import Foundation

// "0.1.3", "v0.2.0": numeric parts compared in order, missing parts count as 0.
public struct Version: Comparable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ string: String) {
        let trimmed = string.hasPrefix("v") ? String(string.dropFirst()) : string
        let parts = trimmed.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(nil) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    // this app's own version, from its Info.plist; nil for a bare binary outside the bundle
    public static var current: Version? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(Version.init)
    }

    public static func < (a: Version, b: Version) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        let pa = a.parts + Array(repeating: 0, count: n - a.parts.count)
        let pb = b.parts + Array(repeating: 0, count: n - b.parts.count)
        return pa.lexicographicallyPrecedes(pb)
    }

    public static func == (a: Version, b: Version) -> Bool { !(a < b) && !(b < a) }

    public var description: String { parts.map(String.init).joined(separator: ".") }
}
