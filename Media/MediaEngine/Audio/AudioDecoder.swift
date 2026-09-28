import Foundation

enum AudioDecoderError: Error, LocalizedError, Sendable {
    case unsupportedCodec(String)
    case setupFailed(String)
    case decodeFailed(String)
    case notReady

    var errorDescription: String? {
        switch self {
        case .unsupportedCodec(let c): return "Unsupported audio codec: \(c)"
        case .setupFailed(let s): return "Audio decoder setup failed: \(s)"
        case .decodeFailed(let s): return "Audio decode failed: \(s)"
        case .notReady: return "Audio decoder not ready"
        }
    }
}

protocol AudioDecoder: AnyObject {
    var codec: AudioCodecID { get }
    var isReady: Bool { get }
    func setup(config: AudioDecoderConfig) throws
    func decode(packet: MediaPacket) throws -> [AudioFrame]
    func flush()
    func invalidate()
}

enum AudioDecoderFactory {
    /// Prefer system decode for AAC/MP3/FLAC; software path for Opus/DTS/etc. later.
    static func make(codec: AudioCodecID) throws -> any AudioDecoder {
        switch codec {
        case .aac, .mp3, .flac, .alac, .pcm:
            return SystemAudioDecoder(codec: codec)
        case .ac3, .eac3:
            // Try system first; may fail on some devices → SoftwareAudioDecoder
            return SystemAudioDecoder(codec: codec)
        case .opus, .vorbis, .dts, .truehd:
            return SoftwareAudioDecoder(codec: codec)
        case .unknown:
            throw AudioDecoderError.unsupportedCodec("unknown")
        }
    }
}
