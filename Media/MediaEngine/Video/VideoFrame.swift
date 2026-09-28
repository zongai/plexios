import CoreMedia
import CoreVideo
import Foundation

/// Decoded video frame ready for Metal (or AVSampleBufferDisplayLayer).
struct VideoFrame: @unchecked Sendable {
    /// Owns the pixel buffer for the duration of rendering.
    let pixelBuffer: CVPixelBuffer
    let ptsMs: Int64?
    let durationMs: Int64?
    let isKeyFrame: Bool
    let width: Int
    let height: Int

    init(
        pixelBuffer: CVPixelBuffer,
        ptsMs: Int64?,
        durationMs: Int64? = nil,
        isKeyFrame: Bool = false
    ) {
        self.pixelBuffer = pixelBuffer
        self.ptsMs = ptsMs
        self.durationMs = durationMs
        self.isKeyFrame = isKeyFrame
        self.width = CVPixelBufferGetWidth(pixelBuffer)
        self.height = CVPixelBufferGetHeight(pixelBuffer)
    }
}

enum VideoCodecID: String, Sendable, Equatable {
    case h264
    case hevc
    case vp9
    case av1
    case unknown

    static func from(codecName: String?) -> VideoCodecID {
        switch IOSCapabilities.normalizeVideoCodec(codecName) {
        case "h264": return .h264
        case "hevc": return .hevc
        case "vp9": return .vp9
        case "av1": return .av1
        default: return .unknown
        }
    }

    var cmVideoCodecType: CMVideoCodecType? {
        switch self {
        case .h264: return kCMVideoCodecType_H264
        case .hevc: return kCMVideoCodecType_HEVC
        case .unknown: return nil
        }
    }
}

struct VideoDecoderConfig: Sendable, Equatable {
    var codec: VideoCodecID
    var width: Int
    var height: Int
    /// AVCDecoderConfigurationRecord / HEVCDecoderConfigurationRecord when available.
    var extradata: Data?
    var bitDepth: Int
}
