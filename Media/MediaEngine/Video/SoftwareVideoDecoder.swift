import Foundation

/// Phase 9 placeholder — FFmpeg software video decode fallback.
final class SoftwareVideoDecoder: VideoDecoder {
    let codec: VideoCodecID
    private(set) var isReady = false

    init(codec: VideoCodecID) {
        self.codec = codec
    }

    func setup(config: VideoDecoderConfig) throws {
        throw VideoDecoderError.unsupportedCodec(
            "Software decoder not implemented (Phase 9). Codec=\(config.codec.rawValue)"
        )
    }

    func decode(packet: MediaPacket) throws -> [VideoFrame] {
        throw VideoDecoderError.notReady
    }

    func flush() {}
    func invalidate() { isReady = false }
}
