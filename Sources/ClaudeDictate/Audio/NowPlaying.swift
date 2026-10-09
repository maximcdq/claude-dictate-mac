import DictateCore
import Foundation

// MARK: - Pause what's playing while dictating
// Music, a video in the browser, a podcast: whatever macOS shows as Now Playing pauses for the length of a dictation
// and plays on afterwards. Only what this app paused is resumed: nothing starts that wasn't playing.
//
// Since macOS 15.4 MediaRemote answers "is anything playing?" only to Apple's own binaries (an app asking itself gets
// false), so the question goes through osascript, which is one; sending the pause and play commands still works from here.

enum NowPlaying {
    private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool
    private static let sendCommand: SendCommand? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW),
              let sym = dlsym(h, "MRMediaRemoteSendCommand") else { return nil }
        return unsafeBitCast(sym, to: SendCommand.self)
    }()
    private static let play: UInt32 = 0, pause: UInt32 = 1  // kMRPlay, kMRPause

    private static let isPlayingScript = """
        ObjC.import('Foundation');
        $.NSBundle.bundleWithPath('/System/Library/PrivateFrameworks/MediaRemote.framework/').load;
        const r = $.NSClassFromString('MRNowPlayingRequest');
        r ? String(r.localIsPlaying) : 'false';
        """

    private static var paused = false
    private static var generation = 0  // a resume while the question is out drops the pause it would lead to

    // Asks off the main thread (osascript takes ~0.1 s) and pauses once the answer is in, unless resume() came first.
    static func pauseIfPlaying() {
        guard sendCommand != nil else { return }
        generation += 1
        let asked = generation
        DispatchQueue.global(qos: .userInitiated).async {
            let playing = isPlaying()
            DispatchQueue.main.async {
                guard playing, asked == generation, !paused else { return }
                paused = sendCommand?(pause, nil) ?? false
                log("media: \(paused ? "paused" : "pause failed")")
            }
        }
    }

    static func resume() {
        generation += 1
        guard paused else { return }
        paused = false
        _ = sendCommand?(play, nil)
        log("media: resumed")
    }

    private static func isPlaying() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-l", "JavaScript", "-e", isPlayingScript]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
}
