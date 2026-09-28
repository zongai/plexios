import CoreVideo
import Foundation

/// FFmpeg-backed software video decoder — fallback when VideoToolbox fails or codec lacks HW (VP9/AV1).
/// Without `NATIVE_FFMPEG` + XCFramework, setup throws so the router can fall back to Plex Transcode.
final class SoftwareVideoDecoder: VideoDecoder {
    let codec: VideoCodecID
    private(set) var isReady = false
    private var config: VideoDecoderConfig?

    #if NATIVE_FFMPEG
    private var codecContext: OpaquePointer?
    #endif

    init(codec: VideoCodecID) {
        self.codec = codec
    }

    deinit { invalidate() }

    func setup(config: VideoDecoderConfig) throws {
        invalidate()
        self.config = config
        #if NATIVE_FFMPEG
        try openFFmpeg(config: config)
        isReady = true
        #else
        throw VideoDecoderError.unsupportedCodec(
            "Software decode for \(config.codec.rawValue) requires NATIVE_FFMPEG (Phase 9). Use Plex Transcode until FFmpeg is linked."
        )
        #endif
    }

    func decode(packet: MediaPacket) throws -> [VideoFrame] {
        guard isReady else { throw VideoDecoderError.notReady }
        #if NATIVE_FFMPEG
        return try decodeFFmpeg(packet)
        #else
        throw VideoDecoderError.notReady
        #endif
    }

    func flush() {}
    func invalidate() {
        #if NATIVE_FFMPEG
        codecContext = nil
        #endif
        isReady = false
        config = nil
    }

    #if NATIVE_FFMPEG
    private func openFFmpeg(config: VideoDecoderConfig) throws {
        throw VideoDecoderError.unsupportedCodec(
            "FFmpegSupport video open not bound — complete C shim for \(config.codec.rawValue)"
        )
    }

    private func decodeFFmpeg(_ packet: MediaPacket) throws -> [VideoFrame] {
        throw VideoDecoderError.noFrame
    }

    static func makeNV12PixelBuffer(width: Int, height: Int, y: Data, uv: Data) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs as CFDictionary,
            &pb
        )
        guard status == kCVReturnSuccess, let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        if let baseY = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            y.withUnsafeBytes { raw in
                guard let src = raw.baseAddress else { return }
                for row in 0..<height {
                    memcpy(baseY.advanced(by: row * bpr), src.advanced(by: row * width), min(width, y.count - row * width))
                }
            }
        }
        if let baseUV = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
            uv.withUnsafeBytes { raw in
                guard let src = raw.baseAddress else { return }
                for row in 0..<(height / 2) {
                    memcpy(baseUV.advanced(by: row * bpr), src.advanced(by: row * width), min(width, uv.count - row * width))
                }
            }
        }
        return pb
    }
    #endif
}

// MARK: - Factory policies

extension VideoDecoderFactory {
    enum Policy: Sendable {
        case hardwareOnly
        case hardwareThenSoftware
        case softwareOnly
    }

    static func make(codec: VideoCodecID, policy: Policy) throws -> any VideoDecoder {
        switch policy {
        case .hardwareOnly:
            return try makeHardware(codec: codec)
        case .softwareOnly:
            return SoftwareVideoDecoder(codec: codec)
        case .hardwareThenSoftware:
            do {
                return try makeHardware(codec: codec)
            } catch {
                return SoftwareVideoDecoder(codec: codec)
            }
        }
    }

    fileprivate static func makeHardware(codec: VideoCodecID) throws -> any VideoDecoder {
        switch codec {
        case .h264, .hevc:
            let caps = VideoToolboxCapabilities.shared
            guard caps.canHardwareDecode(codec) else {
                throw VideoDecoderError.unsupportedCodec(codec.rawValue + " (no HW)")
            }
            return VideoToolboxDecoder(codec: codec)
        case .vp9, .av1, .unknown:
            throw VideoDecoderError.unsupportedCodec(codec.rawValue + " (no HW path)")
        }
    }
}

/// VT → Software → (caller) Transcode
enum VideoDecodeFallbackChain {
    enum Stage: String, Sendable {
        case videoToolbox
        case software
        case failed
    }

    struct Outcome: Sendable {
        var decoder: (any VideoDecoder)?
        var stage: Stage
        var error: String?
    }

    static func open(codec: VideoCodecID) -> Outcome {
        if codec == .h264 || codec == .hevc {
            do {
                let d = try VideoDecoderFactory.make(codec: codec, policy: .hardwareOnly)
                return Outcome(decoder: d, stage: .videoToolbox, error: nil)
            } catch {
                // fall through
            }
        }
        return Outcome(decoder: SoftwareVideoDecoder(codec: codec), stage: .software, error: nil)
    }

    static func setup(_ outcome: Outcome, config: VideoDecoderConfig) throws -> any VideoDecoder {
        guard let decoder = outcome.decoder else {
            throw VideoDecoderError.unsupportedCodec(config.codec.rawValue)
        }
        do {
            try decoder.setup(config: config)
            return decoder
        } catch {
            if outcome.stage == .videoToolbox {
                let soft = SoftwareVideoDecoder(codec: config.codec)
                try soft.setup(config: config)
                return soft
            }
            throw error
        }
    }
}
