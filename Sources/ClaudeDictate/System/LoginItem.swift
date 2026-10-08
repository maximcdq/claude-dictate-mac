import DictateCore
import Foundation

// Start at login: the launchd agent install.sh sets up. Turning it off disables the agent for the next logins
// without stopping the running app (`launchctl disable`, kept by launchd across reboots).
enum LoginItem {
    private static var service: String { "gui/\(getuid())/\(appLabel)" }

    static var isEnabled: Bool {
        get {
            let out = run(["print-disabled", "gui/\(getuid())"]) ?? ""
            let line = out.split(separator: "\n").first { $0.contains("\"\(appLabel)\"") }
            return !(line.map { $0.contains("disabled") || $0.contains("true") } ?? false)
        }
        set {
            _ = run([newValue ? "enable" : "disable", service])
            log("start at login: \(newValue ? "on" : "off")")
        }
    }

    @discardableResult
    private static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
