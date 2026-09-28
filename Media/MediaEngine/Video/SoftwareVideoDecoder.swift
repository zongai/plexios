import CoreVideo
import Foundation

#if NATIVE_FFMPEG
import PlexFFmpeg
#endif

/// FFmpeg-backed software video decoder — fallback when VideoToolbox fails or codec lacks HW (VP9/AV1).
final class SoftwareVideoDecoder: VideoDecoder {
    let codec: VideoCodecID
    private(set) var isReady = false
    private var config: VideoDecoderConfig?

    #if NATIVE_FFMPEG
    private var decoder: OpaquePointer?
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
            "Software decode for \(config.codec.rawValue) requires NATIVE_FFMPEG"
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

    func flush() {
        #if NATIVE_FFMPEG
        if let decoder {
            plex_ff_video_flush(decoder)
        }
        #endif
    }

    func invalidate() {
        #if NATIVE_FFMPEG
        if let decoder {
            plex_ff_video_close(decoder)
        }
        decoder = nil
        #endif
        isReady = false
        config = nil
    }

    #if NATIVE_FFMPEG
    private func openFFmpeg(config: VideoDecoderConfig) throws {
        let name = config.codec.rawValue
        let opened: OpaquePointer? = name.withCString { cName in
            if let extra = config.extradata, !extra.isEmpty {
                return extra.withUnsafeBytes { raw in
                    plex_ff_video_open(
                        cName,
                        Int32(config.width),
                        Int32(config.height),
                        raw.bindMemory(to: UInt8.self).baseAddress,
                        Int32(extra.count)
                    )
                }
            }
            return plex_ff_video_open(cName, Int32(config.width), Int32(config.height), nil, 0)
        }
        guard let opened else {
            throw VideoDecoderError.unsupportedCodec(
                "plex_ff_video_open failed for \(config.codec.rawValue)"
            )
        }
        decoder = opened
    }

    private func decodeFFmpeg(_ packet: MediaPacket) throws -> [VideoFrame] {
        guard let decoder else { throw VideoDecoderError.notReady }

        var outPtr: UnsafeMutablePointer<PlexFFVideoFrame>?
        var outCount: Int32 = 0
        let pts = packet.ptsMs ?? -1
        let key = packet.isKeyFrame ? Int32(1) : Int32(0)

        let rc: Int32 = packet.data.withUnsafeBytes { raw in
            let base = raw.bindMemory(to: UInt8.self).baseAddress
            return plex_ff_video_decode(
                decoder,
                base,
                Int32(packet.data.count),
                pts,
                key,
                &outPtr,
                &outCount
            )
        }

        if rc == 1 {
            return [] // need more data
        }
        if rc < 0 {
            throw VideoDecoderError.decodeFailed(OSStatus(rc))
        }
        guard let outPtr, outCount > 0 else { return [] }

        var frames: [VideoFrame] = []
        frames.reserveCapacity(Int(outCount))
        for i in 0..<Int(outCount) {
            let ff = outPtr[i]
            defer {
                if let nv = ff.nv12 {
                    // free via av_free equivalent - use plex helper on a stack copy
                    var tmp = ff
                    plex_ff_video_frame_free(&tmp)
                }
            }
            guard let nv = ff.nv12, ff.nv12_size > 0, ff.width > 0, ff.height > 0 else { continue }
            let nvData = Data(bytes: nv, count: Int(ff.nv12_size))
            // Clear pointer so free doesn't double-free after we copied — actually we copied and still need free nv12
            let ySize = Int(ff.width * ff.height)
            let y = nvData.prefix(ySize)
            let uv = nvData.dropFirst(ySize)
            guard let pb = Self.makeNV12PixelBuffer(
                width: Int(ff.width),
                height: Int(ff.height),
                y: Data(y),
                uv: Data(uv)
            ) else { continue }
            frames.append(
                VideoFrame(
                    pixelBuffer: pb,
                    ptsMs: ff.pts_ms >= 0 ? ff.pts_ms : packet.ptsMs,
                    durationMs: packet.durationMs,
                    isKeyFrame: ff.is_keyframe != 0
                )
            )
        }
        free(outPtr)
        return frames
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
                    let srcOff = row * width
                    let dstOff = row * bpr
                    let len = min(width, y.count - srcOff)
                    if len > 0 {
                        memcpy(baseY.advanced(by: dstOff), src.advanced(by: srcOff), len)
                    }
                }
            }
        }
        if let baseUV = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
            let bpr = CVPixelBufferGetBytesPerRowOfPlane(pb, 1)
            let uvHeight = height / 2
            uv.withUnsafeBytes { raw in
                guard let src = raw.baseAddress else { return }
                for row in 0..<uvHeight {
                    let srcOff = row * width
                    let dstOff = row * bpr
                    let len = min(width, uv.count - srcOff)
                    if len > 0 {
                        memcpy(baseUV.advanced(by: dstOff), src.advanced(by: srcOff), len)
                    }
                }
            }
        }
        return pb
    }
    #endif
}

// MARK: - Factory policies (unchanged API)

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
