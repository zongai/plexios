import Foundation
import VideoToolbox

/// Runtime VideoToolbox capability probe — never hardcode "HEVC always on".
final class VideoToolboxCapabilities: @unchecked Sendable {
    static let shared = VideoToolboxCapabilities()

    private let lock = NSLock()
    private var cache: [VideoCodecID: Bool] = [:]

    var supportsH264Hardware: Bool { canHardwareDecode(.h264) }
    var supportsHEVCHardware: Bool { canHardwareDecode(.hevc) }

    func canHardwareDecode(_ codec: VideoCodecID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[codec] { return cached }
        let ok: Bool
        switch codec {
        case .h264:
            ok = VTIsHardwareDecodeSupported(kCMVideoCodecType_H264)
        case .hevc:
            ok = VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        case .unknown:
            ok = false
        }
        cache[codec] = ok
        return ok
    }

    /// Build capability records for diagnostics / analyzer.
    func decodeCapabilities() -> [VideoDecodeCapability] {
        var list: [VideoDecodeCapability] = []
        if supportsH264Hardware {
            list.append(VideoDecodeCapability(
                codec: "h264",
                profile: "high",
                bitDepth: 8,
                maxWidth: 4096,
                maxHeight: 2160,
                maxFrameRate: 60,
                hardware: true
            ))
        }
        if supportsHEVCHardware {
            list.append(VideoDecodeCapability(
                codec: "hevc",
                profile: "main",
                bitDepth: 10,
                maxWidth: 4096,
                maxHeight: 2160,
                maxFrameRate: 60,
                hardware: true
            ))
            list.append(VideoDecodeCapability(
                codec: "hevc",
                profile: "main10",
                bitDepth: 10,
                maxWidth: 4096,
                maxHeight: 2160,
                maxFrameRate: 60,
                hardware: true
            ))
        }
        return list
    }

    var summaryLine: String {
        [
            supportsH264Hardware ? "H264:HW" : "H264:no",
            supportsHEVCHardware ? "HEVC:HW" : "HEVC:no"
        ].joined(separator: " ")
    }
}
