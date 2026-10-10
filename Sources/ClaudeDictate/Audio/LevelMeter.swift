import AudioToolbox
import CoreAudio
import DictateAnimations
import DictateCore
import Foundation

// MARK: - Mic level for the indicators
// An AudioQueue at 16 kHz mono 16-bit, the level as Claude Code 2.1.292 computes it: sqrt(min(rms16 / 2000, 1)).
// AVAudioEngine got stuck for good inside Core Audio (enumerating sub-devices) on macOS 27. Opening a queue can still
// block, so it opens off the main thread, and the hotkey's event tap never waits on it; an open that hangs is left behind
// and a fresh one tried.

final class LevelMeter: LevelSource {
    private static let levelQueue = DispatchQueue(label: "meter.level")
    private var recorder: AudioQueueRef?
    private var attempt = 0  // a recorder that opens after a newer attempt (or a stop) is closed at once
    private var restarts = 0
    private var device: AudioDeviceID?
    private let input: () -> AudioDeviceID?  // the device to record from, asked at each start; nil is the default input
    private var lastBufferAt = Date()
    private var restartedAt = Date()
    private(set) var level: CGFloat = 0
    private(set) var heardAt: Date?  // the first audio since start

    init(input: @escaping () -> AudioDeviceID?) {
        self.input = input
    }

    func start() {
        level = 0
        heardAt = nil
        restarts = 0
        device = input()
        open()
    }

    func stop() {
        attempt += 1
        guard let recorder else { return }
        self.recorder = nil
        Self.close(recorder)
    }

    // every frame while recording: a recorder can go quiet without a word when its device changes under it (Claude
    // opening the same mic in another format), so no buffers for a while, even silent ones, means start over
    func watch() {
        let now = Date()
        let backoff = 0.6 * pow(2, Double(min(restarts, 3)))  // a wedged Core Audio is not hammered
        guard now.timeIntervalSince(lastBufferAt) > 0.4, now.timeIntervalSince(restartedAt) > backoff else { return }
        restarts += 1
        log("mic: no audio reaching the indicator, restarting its recorder")
        stop()
        open()
    }

    private func open() {
        restartedAt = Date()
        lastBufferAt = Date()
        attempt += 1
        let attempt = attempt, device = self.device
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let recorder = Self.openRecorder(device: device) { v in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.level = v
                    self.lastBufferAt = Date()
                    if self.heardAt == nil { self.heardAt = self.lastBufferAt }
                }
            }
            DispatchQueue.main.async {
                guard let recorder else { return }
                guard let self, attempt == self.attempt else { return Self.close(recorder) }
                self.recorder = recorder
            }
        }
    }

    private static func close(_ recorder: AudioQueueRef) {
        DispatchQueue.global(qos: .utility).async {
            AudioQueueStop(recorder, true)
            AudioQueueDispose(recorder, true)
        }
    }

    // off the main thread: may block while Core Audio is busy
    private static func openRecorder(device: AudioDeviceID?, onLevel: @escaping (CGFloat) -> Void) -> AudioQueueRef? {
        var format = AudioStreamBasicDescription(
            mSampleRate: 16000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var queue: AudioQueueRef?
        let status = AudioQueueNewInputWithDispatchQueue(&queue, &format, 0, levelQueue) { q, buffer, _, _, _ in
            let n = Int(buffer.pointee.mAudioDataByteSize) / 2
            let samples = buffer.pointee.mAudioData.assumingMemoryBound(to: Int16.self)
            var sum: Float = 0
            for i in 0..<n { let v = Float(samples[i]); sum += v * v }
            AudioQueueEnqueueBuffer(q, buffer, 0, nil)
            let rms16 = sqrt(sum / Float(max(n, 1)))  // Claude measures 16-bit samples, as these are
            onLevel(CGFloat(sqrt(min(rms16 / 2000, 1))))
        }
        guard status == noErr, let queue else { log("mic: AudioQueueNewInput failed (\(status))"); return nil }
        // bound to the device itself: a recorder on the default input goes silent when the default moves to the
        // built-in mic right under it
        if let device, let uid = Mic.uid(device) {
            var cfUID = uid as CFString
            let set = withUnsafeMutablePointer(to: &cfUID) {
                AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, $0, UInt32(MemoryLayout<CFString>.size))
            }
            if set != noErr { log("mic: binding the recorder to \(uid) failed (\(set))") }
        }
        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(queue, 1600, &buffer)  // 50 ms
            if let buffer { AudioQueueEnqueueBuffer(queue, buffer, 0, nil) }
        }
        let started = AudioQueueStart(queue, nil)
        guard started == noErr else {
            log("mic: AudioQueueStart failed (\(started))")
            AudioQueueDispose(queue, true)
            return nil
        }
        return queue
    }
}
