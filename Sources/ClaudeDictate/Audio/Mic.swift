import CoreAudio
import DictateCore
import Foundation

// MARK: - Built-in mic for dictation
// Claude records from the system default input, which macOS moves to AirPods whenever they connect. For the
// length of a dictation the default input is the Mac's own mic (AirPods stay in their high-quality mode),
// then it goes back to whatever it was.

enum Mic {
    private static func address(_ selector: AudioObjectPropertySelector,
                                _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static var defaultInput: AudioDeviceID {
        get {
            var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var a = address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &id)
            return id
        }
        set {
            var id = newValue
            var a = address(kAudioHardwarePropertyDefaultInputDevice)
            AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil,
                                       UInt32(MemoryLayout<AudioDeviceID>.size), &id)
        }
    }

    static var builtIn: AudioDeviceID? {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids)
        return ids.first { id in
            var transport: UInt32 = 0, tsize = UInt32(MemoryLayout<UInt32>.size)
            var t = address(kAudioDevicePropertyTransportType)
            AudioObjectGetPropertyData(id, &t, 0, nil, &tsize, &transport)
            var streams = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
            var ssize: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &ssize)
            return transport == kAudioDeviceTransportTypeBuiltIn && ssize > 0
        }
    }

    // The input to go back to, kept on disk by UID (device ids change across reboots and reconnects): if the app
    // dies mid-dictation, the next start puts it back.
    private static let previousFile = "\(Paths.state)/previous-input.txt"

    static func uid(_ id: AudioDeviceID) -> String? {
        var a = address(kAudioDevicePropertyDeviceUID)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr else { return nil }
        return value?.takeRetainedValue() as String?
    }

    private static func device(uid: String) -> AudioDeviceID? {
        var a = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var id = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) {
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a,
                                       UInt32(MemoryLayout<CFString>.size), $0, &size, &id)
        }
        return status == noErr && id != 0 ? id : nil
    }

    static func useBuiltIn() {
        guard let mac = builtIn else { log("mic: no built-in input found"); return }
        let current = defaultInput
        guard current != mac, let currentUID = uid(current) else { return }
        try? currentUID.write(toFile: previousFile, atomically: true, encoding: .utf8)
        defaultInput = mac
        log("mic: built-in (\(defaultInput == mac ? "switched" : "switch failed"), was \(currentUID))")
    }

    // also called at launch, to undo a switch a crashed run left behind
    static func restore() {
        guard let prevUID = try? String(contentsOfFile: previousFile, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(atPath: previousFile)
        // unless the user picked another input meanwhile, or that device is gone (AirPods put away)
        guard let mac = builtIn, defaultInput == mac, let prev = device(uid: prevUID) else { return }
        defaultInput = prev
        log("mic: restored \(prevUID)")
    }
}
