import Foundation

// Where the app keeps its state. The hidden Claude Code session and its helper mod read and write here too.
public enum Paths {
    public static let home = FileManager.default.homeDirectoryForCurrentUser.path
    public static let state = "\(home)/Library/Application Support/ClaudeDictate"
    public static let live = "\(state)/live.txt"  // the prompt draft, mirrored by the mod
    public static let control = "\(state)/control.txt"  // "clear" from the app empties the prompt
    public static let agent = "\(state)/agent"  // the hidden session's working folder
    public static let mod = "\(state)/mod"  // the mod, copied out of the app bundle (Claude Code writes next to it)
    public static let log = "\(home)/Library/Logs/ClaudeDictate.log"
    public static let caches = "\(home)/Library/Caches/ClaudeDictate"
}

// Claude Code's native install keeps its last few versions in one folder. The newest one that is executable (an
// auto-update writes a version before it makes it executable) and not in `avoiding`; with all of them avoided, the newest.
public func claudeVersion(in dir: String, avoiding: Set<String> = []) -> String? {
    let fm = FileManager.default
    let modified = { (path: String) in (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast }
    let versions = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).map { "\(dir)/\($0)" }
        .filter { fm.isExecutableFile(atPath: $0) }
        .sorted { modified($0) > modified($1) }
    return versions.first { !avoiding.contains($0) } ?? versions.first
}

// The launchd job install.sh sets up, also the bundle identifier and the code signing identifier.
public let appLabel = "local.claude-dictate"
