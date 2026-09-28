import AVFoundation
import Foundation

enum AudioRendererError: Error, LocalizedError {
    case engineStartFailed(String)
    case formatUnavailable

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let s): return "Audio engine start failed: \(s)"
        case .formatUnavailable: return "Audio format unavailable"
        }
    }
}

/// Plays PCM `AudioFrame`s via `AVAudioEngine` + `AVAudioPlayerNode`.
/// Coordinates with existing `AudioSessionCoordinator` (category already set by PlaybackEngine).
final class AudioRenderer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var format: AVAudioFormat?
    private var isStarted = false
    private let lock = NSLock()

    private(set) var sampleRate: Double = 48_000
    private(set) var channelCount: Int = 2

    /// Playback rate (0.5…2.0) applied via player node.
    var rate: Float = 1.0 {
        didSet {
            player.rate = max(0.5, min(rate, 2.0))
        }
    }

    var isPlaying: Bool { player.isPlaying }

    init() {
        engine.attach(player)
    }

    deinit {
        stop()
    }

    func prepare(sampleRate: Double, channels: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        self.sampleRate = sampleRate
        self.channelCount = max(channels, 1)
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(self.channelCount),
            interleaved: true
        ) else {
            throw AudioRendererError.formatUnavailable
        }
        format = fmt

        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: fmt)

        if !isStarted {
            do {
                try engine.start()
                isStarted = true
            } catch {
                throw AudioRendererError.engineStartFailed(error.localizedDescription)
            }
        }
    }

    func enqueue(_ frame: AudioFrame) {
        lock.lock()
        defer { lock.unlock() }
        guard let format else { return }

        if format.sampleRate != frame.sampleRate
            || Int(format.channelCount) != frame.channelCount {
            // Format change — re-prepare on next prepare() call
            return
        }

        let frameCount = AVAudioFrameCount(frame.frameCount)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
        else { return }
        buffer.frameLength = frameCount

        frame.pcm.withUnsafeBytes { raw in
            guard let src = raw.bindMemory(to: Float.self).baseAddress,
                  let dst = buffer.floatChannelData?[0]
            else { return }
            dst.update(from: src, count: Int(frameCount) * Int(format.channelCount))
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    func play() {
        if !player.isPlaying { player.play() }
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
        player.reset()
        if isStarted {
            engine.stop()
            isStarted = false
        }
    }

    func flush() {
        player.stop()
        player.reset()
    }

    /// Approximate rendered position from player node time.
    func currentTimeMs() -> Int64? {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        let seconds = Double(playerTime.sampleTime) / playerTime.sampleRate
        return Int64(seconds * 1000)
    }
}
