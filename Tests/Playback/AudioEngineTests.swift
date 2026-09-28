import XCTest
@testable import PlexiOS

final class AudioEngineTests: XCTestCase {
    func testCodecIDMapping() {
        XCTAssertEqual(AudioCodecID.from(codecName: "aac"), .aac)
        XCTAssertEqual(AudioCodecID.from(codecName: "eac3"), .eac3)
        XCTAssertEqual(AudioCodecID.from(codecName: "opus"), .opus)
        XCTAssertEqual(AudioCodecID.from(codecName: "dca"), .dts)
    }

    func testFactoryAAC() throws {
        let dec = try AudioDecoderFactory.make(codec: .aac)
        XCTAssertEqual(dec.codec, .aac)
        try dec.setup(config: AudioDecoderConfig(
            codec: .aac,
            sampleRate: 48_000,
            channels: 2,
            extradata: nil,
            bitDepth: 16
        ))
        XCTAssertTrue(dec.isReady)
        dec.invalidate()
    }

    func testSoftwareOpusRequiresFFmpeg() {
        let soft = SoftwareAudioDecoder(codec: .opus)
        XCTAssertThrowsError(try soft.setup(config: AudioDecoderConfig(
            codec: .opus, sampleRate: 48_000, channels: 2, extradata: nil, bitDepth: 16
        )))
    }

    func testPCMPassthrough() throws {
        let dec = try AudioDecoderFactory.make(codec: .pcm)
        try dec.setup(config: AudioDecoderConfig(
            codec: .pcm, sampleRate: 48_000, channels: 1, extradata: nil, bitDepth: 16
        ))
        // 4 samples S16 mono silence
        var samples = [Int16](repeating: 0, count: 4)
        let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
        let packet = MediaPacket(
            kind: .audio, streamIndex: 0, data: data,
            ptsMs: 0, dtsMs: 0, durationMs: nil, isKeyFrame: false
        )
        let frames = try dec.decode(packet: packet)
        XCTAssertEqual(frames.count, 1)
        XCTAssertGreaterThan(frames[0].pcm.count, 0)
        dec.invalidate()
    }

    func testRendererPrepare() throws {
        let r = AudioRenderer()
        try r.prepare(sampleRate: 48_000, channels: 2)
        r.rate = 1.25
        r.stop()
    }
}
