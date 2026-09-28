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

/// Hardware-first video decoder surface (VideoToolbox in Phase 3).
protocol VideoDecoder: AnyObject {
    var codec: VideoCodecID { get }
    var isReady: Bool { get }

    func setup(config: VideoDecoderConfig) throws
    /// Feed one encoded access unit / NAL set. May output 0..n frames asynchronously depending on implementation.
    func decode(packet: MediaPacket) throws -> [VideoFrame]
    func flush()
    func invalidate()
}

enum VideoDecoderFactory {
    /// Prefer VideoToolbox for H.264/HEVC when hardware reports support.
    static func make(codec: VideoCodecID) throws -> any VideoDecoder {
        switch codec {
        case .h264, .hevc:
            let caps = VideoToolboxCapabilities.shared
            guard caps.canHardwareDecode(codec) else {
                throw VideoDecoderError.unsupportedCodec(codec.rawValue + " (no HW)")
            }
            return VideoToolboxDecoder(codec: codec)
        case .unknown:
            throw VideoDecoderError.unsupportedCodec("unknown")
        }
    }
}
