import Foundation

/// Bounded queues for packets and decoded frames.
final class BufferManager: @unchecked Sendable {
    struct Limits: Sendable {
        var maxVideoPackets: Int = 80
        var maxAudioPackets: Int = 120
        var maxSubtitlePackets: Int = 40
        var maxVideoFrames: Int = 8
        var maxAudioFrames: Int = 32
        /// Target startup buffered media duration before play (ms).
        var startupTargetMs: Int64 = 300
        var rebufferTargetMs: Int64 = 500
    }

    private let lock = NSLock()
    private let limits: Limits

    private var videoPackets: [MediaPacket] = []
    private var audioPackets: [MediaPacket] = []
    private var subtitlePackets: [MediaPacket] = []
    private var videoFrames: [VideoFrame] = []
    private var audioFrames: [AudioFrame] = []

    init(limits: Limits = Limits()) {
        self.limits = limits
    }

    // MARK: - Push

    @discardableResult
    func pushPacket(_ packet: MediaPacket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        switch packet.kind {
        case .video:
            if videoPackets.count >= limits.maxVideoPackets { return false }
            videoPackets.append(packet)
        case .audio:
            if audioPackets.count >= limits.maxAudioPackets { return false }
            audioPackets.append(packet)
        case .subtitle:
            if subtitlePackets.count >= limits.maxSubtitlePackets { return false }
            subtitlePackets.append(packet)
        case .unknown:
            return false
        }
        return true
    }

    @discardableResult
    func pushVideoFrame(_ frame: VideoFrame) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if videoFrames.count >= limits.maxVideoFrames { return false }
        videoFrames.append(frame)
        return true
    }

    @discardableResult
    func pushAudioFrame(_ frame: AudioFrame) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if audioFrames.count >= limits.maxAudioFrames { return false }
        audioFrames.append(frame)
        return true
    }

    // MARK: - Pop

    func popVideoPacket() -> MediaPacket? {
        lock.lock(); defer { lock.unlock() }
        guard !videoPackets.isEmpty else { return nil }
        return videoPackets.removeFirst()
    }

    func popAudioPacket() -> MediaPacket? {
        lock.lock(); defer { lock.unlock() }
        guard !audioPackets.isEmpty else { return nil }
        return audioPackets.removeFirst()
    }

    func popSubtitlePacket() -> MediaPacket? {
        lock.lock(); defer { lock.unlock() }
        guard !subtitlePackets.isEmpty else { return nil }
        return subtitlePackets.removeFirst()
    }

    func popVideoFrame() -> VideoFrame? {
        lock.lock(); defer { lock.unlock() }
        guard !videoFrames.isEmpty else { return nil }
        return videoFrames.removeFirst()
    }

    func peekVideoFrame() -> VideoFrame? {
        lock.lock(); defer { lock.unlock() }
        return videoFrames.first
    }

    func popAudioFrame() -> AudioFrame? {
        lock.lock(); defer { lock.unlock() }
        guard !audioFrames.isEmpty else { return nil }
        return audioFrames.removeFirst()
    }

    // MARK: - Metrics

    func counts() -> (vPkt: Int, aPkt: Int, vFrm: Int, aFrm: Int) {
        lock.lock(); defer { lock.unlock() }
        return (videoPackets.count, audioPackets.count, videoFrames.count, audioFrames.count)
    }

    /// Approximate buffered A/V duration from packet PTS span.
    func bufferedDurationMs() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let pts = (videoPackets.compactMap(\.ptsMs) + audioPackets.compactMap(\.ptsMs)).sorted()
        guard let first = pts.first, let last = pts.last, last >= first else { return 0 }
        return last - first
    }

    func hasStartupBuffer() -> Bool {
        bufferedDurationMs() >= limits.startupTargetMs || counts().vFrm > 0
    }

    func needsRebuffer() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return videoPackets.isEmpty && videoFrames.isEmpty && audioPackets.isEmpty && audioFrames.isEmpty
    }

    func flushAll() {
        lock.lock(); defer { lock.unlock() }
        videoPackets.removeAll()
        audioPackets.removeAll()
        subtitlePackets.removeAll()
        videoFrames.removeAll()
        audioFrames.removeAll()
    }
}
