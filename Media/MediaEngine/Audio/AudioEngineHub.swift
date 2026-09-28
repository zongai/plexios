import Foundation

/// Thin façade: choose decoder + feed renderer. Used by Native pipeline (Phase 6 clock owns pacing).
final class AudioEngineHub {
    private var decoder: (any AudioDecoder)?
    private let renderer = AudioRenderer()
    private(set) var lastError: String?

    var rate: Float {
        get { renderer.rate }
        set { renderer.rate = newValue }
    }

    func setup(config: AudioDecoderConfig) throws {
        lastError = nil
        decoder?.invalidate()
        let dec = try AudioDecoderFactory.make(codec: config.codec)
        try dec.setup(config: config)
        decoder = dec
        try renderer.prepare(
            sampleRate: Double(max(config.sampleRate, 8000)),
            channels: config.channels
        )
    }

    func push(packet: MediaPacket) throws {
        guard let decoder else { throw AudioDecoderError.notReady }
        let frames = try decoder.decode(packet: packet)
        for frame in frames {
            renderer.enqueue(frame)
        }
    }

    func play() { renderer.play() }
    func pause() { renderer.pause() }
    func stop() {
        renderer.stop()
        decoder?.invalidate()
        decoder = nil
    }

    func flush() {
        decoder?.flush()
        renderer.flush()
    }

    func currentTimeMs() -> Int64? { renderer.currentTimeMs() }
}
