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

// The launchd job install.sh sets up, also the bundle identifier and the code signing identifier.
public let appLabel = "local.claude-dictate"
