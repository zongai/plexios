import Foundation

/// Software audio path for codecs system AudioConverter cannot handle (Opus, DTS, TrueHD…).
/// Phase 5: stub that reports clear errors until FFmpeg `libavcodec` is linked (`NATIVE_FFMPEG`).
final class SoftwareAudioDecoder: AudioDecoder {
    let codec: AudioCodecID
    private(set) var isReady = false
    private var config: AudioDecoderConfig?

    init(codec: AudioCodecID) {
        self.codec = codec
    }

    func setup(config: AudioDecoderConfig) throws {
        self.config = config
        #if NATIVE_FFMPEG
        // Future: avcodec_open2 for opus/dca/truehd → float planar → interleaved
        isReady = true
        #else
        throw AudioDecoderError.unsupportedCodec(
            "\(codec.rawValue) requires SoftwareAudioDecoder + NATIVE_FFMPEG (Phase 5/9)"
        )
        #endif
    }

    func decode(packet: MediaPacket) throws -> [AudioFrame] {
        #if NATIVE_FFMPEG
        throw AudioDecoderError.decodeFailed("FFmpeg audio decode not bound yet")
        #else
        throw AudioDecoderError.notReady
        #endif
    }

    func flush() {}
    func invalidate() {
        isReady = false
        config = nil
    }
}
