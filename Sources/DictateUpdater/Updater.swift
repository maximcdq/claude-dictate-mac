import CryptoKit
import DictateCore
import Foundation

// Self-update from the GitHub releases of the repo: the release workflow attaches ClaudeDictate.zip (the app,
// ad-hoc signed) to every release. A newer one is downloaded, checked (its SHA-256 against GitHub's digest, its bundle
// identifier and version), signed again with the local identity install.sh created (so macOS keeps the Accessibility
// and Microphone permissions, which belong to the signature) and swapped in for the running app. The app then
// restarts into it.
public final class Updater {
    public struct Config {
        public var repo = "maximcdq/claude-dictate-mac"
        public var asset = "ClaudeDictate.zip"
        public var signingIdentity = "ClaudeDictate Local Signing"
        public init() {}
    }

    public enum State: Equatable {
        case idle
        case checking
        case upToDate
        case installing(String)
        case installed(String)  // waiting for the app to restart into it
        case failed(String)
    }

    public private(set) var state = State.idle { didSet { onChange?(state) } }
    public var onChange: ((State) -> Void)?
    public var canInstall: () -> Bool = { true }  // not mid-dictation
    public var onInstalled: (String) -> Void = { _ in }  // restart into the new version

    private let config: Config
    private var timer: Timer?
    private static let checkEvery: TimeInterval = 4 * 3600

    public init(config: Config = Config()) {
        self.config = config
    }

    public var currentVersion: String { Version.current?.description ?? "dev" }

    // a first check shortly after launch, then every few hours
    public func setAutomatic(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, self.timer != nil else { return }
            self.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkEvery, repeats: true) { [weak self] _ in self?.check() }
    }

    public func check() {
        switch state {
        case .checking, .installing, .installed: return
        default: break
        }
        guard let current = Version.current else { return log("update: a bare binary, not an installed app: no updates") }
        state = .checking
        Task {
            do {
                let release = try await latestRelease()
                guard let latest = Version(release.tag_name), latest > current else {
                    await MainActor.run { self.state = .upToDate }
                    return
                }
                guard let asset = release.assets.first(where: { $0.name == config.asset }) else {
                    log("update: \(release.tag_name) has no \(config.asset) yet")
                    await MainActor.run { self.state = .upToDate }
                    return
                }
                await MainActor.run { self.install(latest, asset) }
            } catch {
                log("update: check failed: \(error)")
                await MainActor.run { self.state = .failed("Couldn't reach GitHub") }
            }
        }
    }

    private func install(_ version: Version, _ asset: Release.Asset) {
        guard canInstall() else {
            state = .idle
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in self?.check() }  // after the dictation
            return
        }
        state = .installing(version.description)
        log("update: installing \(version)")
        Task.detached { [config] in
            do {
                let app = try await Self.download(asset, version: version, config: config)
                try Self.swap(in: app)
                log("update: installed \(version)")
                await MainActor.run {
                    self.state = .installed(version.description)
                    self.onInstalled(version.description)
                }
            } catch {
                log("update: \(version) failed: \(error)")
                await MainActor.run { self.state = .failed("Update to \(version) failed: \(error)") }
            }
        }
    }

    // MARK: GitHub

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
            let digest: String?  // "sha256:…"
        }
        let tag_name: String
        let assets: [Asset]
    }

    private func latestRelease() async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(config.repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0)") }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    // MARK: Download, verify, sign

    private static func download(_ asset: Release.Asset, version: Version, config: Config) async throws -> URL {
        let work = URL(fileURLWithPath: Paths.caches).appendingPathComponent("update")
        let fm = FileManager.default
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let (file, response) = try await URLSession.shared.download(from: asset.browser_download_url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("download answered \((response as? HTTPURLResponse)?.statusCode ?? 0)") }
        let zip = work.appendingPathComponent(asset.name)
        try fm.moveItem(at: file, to: zip)

        if let digest = asset.digest, digest.hasPrefix("sha256:") {
            let sum = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
            guard "sha256:\(sum)" == digest else { throw UpdateError("checksum mismatch") }
        }

        try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
        let app = work.appendingPathComponent("ClaudeDictate.app")
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == appLabel else { throw UpdateError("not ClaudeDictate") }
        guard (info?["CFBundleShortVersionString"] as? String).flatMap(Version.init) == version else { throw UpdateError("version mismatch") }

        // the local identity keeps the permissions; without it (an install not made by install.sh) an ad-hoc
        // signature still runs, and macOS asks for the permissions again
        do {
            try run("/usr/bin/codesign", ["--force", "--sign", config.signingIdentity, "--identifier", appLabel, app.path])
        } catch {
            log("update: no local signing identity (\(error)), signing ad hoc: permissions will be asked again")
            try run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", appLabel, app.path])
        }
        try run("/usr/bin/codesign", ["--verify", "--strict", app.path])
        return app
    }

    // the new bundle takes the running one's place; the old one goes back if the move fails
    private static func swap(in app: URL) throws {
        let fm = FileManager.default
        let installed = Bundle.main.bundleURL
        let old = app.deletingLastPathComponent().appendingPathComponent("previous.app")
        try? fm.removeItem(at: old)
        try fm.moveItem(at: installed, to: old)
        do {
            try fm.moveItem(at: app, to: installed)
        } catch {
            try? fm.moveItem(at: old, to: installed)
            throw error
        }
        try? fm.removeItem(at: old)
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("\((tool as NSString).lastPathComponent): \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return out
    }
}

struct UpdateError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
