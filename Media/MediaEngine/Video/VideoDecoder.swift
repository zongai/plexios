import Foundation

enum VideoDecoderError: Error, LocalizedError, Sendable {
    case unsupportedCodec(String)
    case formatDescriptionFailed(String)
    case sessionCreateFailed(OSStatus)
    case decodeFailed(OSStatus)
    case notReady
    case noFrame

    var errorDescription: String? {
        switch self {
        case .unsupportedCodec(let c): return "Unsupported video codec: \(c)"
        case .formatDescriptionFailed(let s): return "Format description failed: \(s)"
        case .sessionCreateFailed(let s): return "VT session create failed: \(s)"
        case .decodeFailed(let s): return "VT decode failed: \(s)"
        case .notReady: return "Video decoder not ready"
        case .noFrame: return "No frame produced"
        }
    }
}

/// Hardware-first video decoder surface (VideoToolbox + software fallback).
protocol VideoDecoder: AnyObject {
    var codec: VideoCodecID { get }
    var isReady: Bool { get }

    func setup(config: VideoDecoderConfig) throws
    func decode(packet: MediaPacket) throws -> [VideoFrame]
    func flush()
    func invalidate()
}

enum VideoDecoderFactory {
    /// Prefer VideoToolbox for H.264/HEVC when hardware reports support.
    /// For VP9/AV1 returns software decoder instance (setup may still need NATIVE_FFMPEG).
    static func make(codec: VideoCodecID) throws -> any VideoDecoder {
        try make(codec: codec, policy: .hardwareThenSoftware)
    }
}
