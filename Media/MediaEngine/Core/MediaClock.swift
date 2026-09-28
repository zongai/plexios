import Foundation

/// Master clock for Native Media Engine. Audio is preferred master when available.
final class MediaClock: @unchecked Sendable {
    enum Master: String, Sendable {
        case audio
        case video
        case external
    }

    private let lock = NSLock()
    private var master: Master = .external
    private var startedAt: ContinuousClock.Instant?
    private var pausedAccumulated: Duration = .zero
    private var pauseBegan: ContinuousClock.Instant?
    private var rate: Double = 1.0
    private var seekOffsetMs: Int64 = 0

    /// Last known media time from audio renderer (ms).
    private var audioPtsMs: Int64?
    /// Last presented video PTS (ms).
    private var videoPtsMs: Int64?

    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return pauseBegan != nil
    }

    var playbackRate: Double {
        get { lock.lock(); defer { lock.unlock() }; return rate }
        set {
            lock.lock()
            rate = max(0.25, min(newValue, 2.0))
            lock.unlock()
        }
    }

    func reset(startMs: Int64 = 0) {
        lock.lock()
        startedAt = ContinuousClock.now
        pausedAccumulated = .zero
        pauseBegan = nil
        seekOffsetMs = startMs
        audioPtsMs = nil
        videoPtsMs = nil
        master = .external
        lock.unlock()
    }

    func pause() {
        lock.lock()
        if pauseBegan == nil {
            pauseBegan = .now
        }
        lock.unlock()
    }

    func resume() {
        lock.lock()
        if let began = pauseBegan {
            pausedAccumulated += ContinuousClock.now - began
            pauseBegan = nil
        }
        lock.unlock()
    }

    func seek(toMs ms: Int64) {
        lock.lock()
        seekOffsetMs = ms
        startedAt = .now
        pausedAccumulated = .zero
        pauseBegan = nil
        audioPtsMs = ms
        videoPtsMs = ms
        lock.unlock()
    }

    func setAudioPts(_ ms: Int64?) {
        lock.lock()
        audioPtsMs = ms
        if ms != nil { master = .audio }
        lock.unlock()
    }

    func setVideoPts(_ ms: Int64?) {
        lock.lock()
        videoPtsMs = ms
        if master != .audio, ms != nil { master = .video }
        lock.unlock()
    }

    /// Current media time in milliseconds.
    func currentMediaTimeMs() -> Int64 {
        lock.lock()
        defer { lock.unlock() }

        if let audio = audioPtsMs, master == .audio {
            return audio
        }
        if let video = videoPtsMs, master == .video {
            return video
        }

        guard let startedAt else { return seekOffsetMs }
        var elapsed = ContinuousClock.now - startedAt - pausedAccumulated
        if let pauseBegan {
            elapsed -= ContinuousClock.now - pauseBegan
        }
        let seconds = Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / 1e18
        return seekOffsetMs + Int64(seconds * rate * 1000)
    }

    /// How far video is ahead of master clock (positive = video early).
    func videoSkewMs(videoPts: Int64) -> Int64 {
        videoPts - currentMediaTimeMs()
    }
}
