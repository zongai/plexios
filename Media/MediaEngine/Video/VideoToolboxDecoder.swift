import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

/// H.264 / HEVC hardware decoder via VideoToolbox.
///
/// Prefer **AVCC / HVCC** (4-byte length-prefixed NALs) with `avcC` / `hvcC` extradata.
/// Annex-B start codes are converted when detected.
final class VideoToolboxDecoder: VideoDecoder {
    let codec: VideoCodecID
    private(set) var isReady = false

    private var session: VTDecompressionSession?
    private var formatDescription: CMVideoFormatDescription?
    private var config: VideoDecoderConfig?
    private let outputLock = NSLock()
    private var pendingFrames: [VideoFrame] = []

    init(codec: VideoCodecID) {
        self.codec = codec
    }

    deinit {
        invalidate()
    }

    func setup(config: VideoDecoderConfig) throws {
        invalidate()
        self.config = config
        guard config.codec == codec else {
            throw VideoDecoderError.unsupportedCodec("config mismatch \(config.codec.rawValue)")
        }
        guard let codecType = codec.cmVideoCodecType else {
            throw VideoDecoderError.unsupportedCodec(codec.rawValue)
        }

        let formatDesc = try Self.makeFormatDescription(
            codecType: codecType,
            extradata: config.extradata,
            width: config.width,
            height: config.height
        )
        formatDescription = formatDesc

        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: Self.outputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(self).toOpaque()
        )

        var pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        if config.bitDepth >= 10 {
            pixelFormat = kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
        }
        let imageAttrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]

        var sessionOut: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDesc,
            decoderSpecification: [
                kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: kCFBooleanTrue as Any
            ] as CFDictionary,
            imageBufferAttributes: imageAttrs as CFDictionary,
            outputCallback: &callback,
            decompressionSessionOut: &sessionOut
        )
        guard status == noErr, let sessionOut else {
            throw VideoDecoderError.sessionCreateFailed(status)
        }
        session = sessionOut
        isReady = true
    }

    func decode(packet: MediaPacket) throws -> [VideoFrame] {
        guard isReady, let session, let formatDescription else {
            throw VideoDecoderError.notReady
        }
        guard packet.kind == .video, !packet.data.isEmpty else {
            return []
        }

        let data = Self.ensureLengthPrefixed(packet.data)
        let blockBuffer = try Self.makeOwnedBlockBuffer(data)

        var timing = CMSampleTimingInfo(
            duration: packet.durationMs.map { CMTime(value: $0, timescale: 1000) } ?? .invalid,
            presentationTimeStamp: packet.ptsMs.map { CMTime(value: $0, timescale: 1000) } ?? .zero,
            decodeTimeStamp: packet.dtsMs.map { CMTime(value: $0, timescale: 1000) } ?? .invalid
        )
        var sampleSize = data.count
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else {
            throw VideoDecoderError.decodeFailed(createStatus)
        }

        outputLock.lock()
        pendingFrames.removeAll(keepingCapacity: true)
        outputLock.unlock()

        var flagsOut: VTDecodeInfoFlags = []
        let decodeStatus = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [._EnableAsynchronousDecompression],
            frameRefcon: nil,
            infoFlagsOut: &flagsOut
        )
        VTDecompressionSessionWaitForAsynchronousFrames(session)

        if decodeStatus != noErr {
            throw VideoDecoderError.decodeFailed(decodeStatus)
        }

        outputLock.lock()
        let frames = pendingFrames
        pendingFrames.removeAll(keepingCapacity: true)
        outputLock.unlock()
        return frames
    }

    func flush() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
        }
        outputLock.lock()
        pendingFrames.removeAll()
        outputLock.unlock()
    }

    func invalidate() {
        flush()
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        session = nil
        formatDescription = nil
        isReady = false
    }

    // MARK: - Callback

    private static let outputCallback: VTDecompressionOutputCallback = {
        refCon, _, status, _, imageBuffer, pts, duration in
        guard status == noErr, let imageBuffer, let refCon else { return }
        let decoder = Unmanaged<VideoToolboxDecoder>.fromOpaque(refCon).takeUnretainedValue()
        let ptsMs: Int64? = pts.isValid ? Int64((pts.seconds * 1000.0).rounded()) : nil
        let durationMs: Int64? = duration.isValid ? Int64((duration.seconds * 1000.0).rounded()) : nil
        let frame = VideoFrame(
            pixelBuffer: imageBuffer,
            ptsMs: ptsMs,
            durationMs: durationMs,
            isKeyFrame: false
        )
        decoder.outputLock.lock()
        decoder.pendingFrames.append(frame)
        decoder.outputLock.unlock()
    }

    // MARK: - Format description

    private static func makeFormatDescription(
        codecType: CMVideoCodecType,
        extradata: Data?,
        width: Int,
        height: Int
    ) throws -> CMVideoFormatDescription {
        let w = Int32(max(width, 16))
        let h = Int32(max(height, 16))

        if let extradata, !extradata.isEmpty {
            let atomKey: String
            if codecType == kCMVideoCodecType_H264 {
                atomKey = "avcC"
            } else if codecType == kCMVideoCodecType_HEVC {
                atomKey = "hvcC"
            } else {
                throw VideoDecoderError.unsupportedCodec("\(codecType)")
            }
            let atoms = [atomKey: extradata] as CFDictionary
            let extensions = [
                kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms
            ] as CFDictionary
            var desc: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: codecType,
                width: w,
                height: h,
                extensions: extensions,
                formatDescriptionOut: &desc
            )
            guard status == noErr, let desc else {
                throw VideoDecoderError.formatDescriptionFailed("\(atomKey) status \(status)")
            }
            return desc
        }

        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: codecType,
            width: w,
            height: h,
            extensions: nil,
            formatDescriptionOut: &desc
        )
        guard status == noErr, let desc else {
            throw VideoDecoderError.formatDescriptionFailed("status \(status)")
        }
        return desc
    }

    private static func makeOwnedBlockBuffer(_ data: Data) throws -> CMBlockBuffer {
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw VideoDecoderError.decodeFailed(status)
        }
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else {
                throw VideoDecoderError.decodeFailed(OSStatus(paramErr))
            }
            let replace = CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: data.count
            )
            if replace != noErr {
                throw VideoDecoderError.decodeFailed(replace)
            }
        }
        return blockBuffer
    }

    /// Convert Annex-B to 4-byte length-prefixed NALs when start codes are present.
    private static func ensureLengthPrefixed(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 4 else { return data }

        // Heuristic: already AVCC if size field looks sane
        let n = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        if n > 0, n + 4 <= bytes.count, n < bytes.count {
            return data
        }

        var nals: [(Int, Int)] = [] // start, length
        var i = 0
        while i + 3 < bytes.count {
            var sc = 0
            if bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 1 {
                sc = 3
            } else if i + 4 < bytes.count, bytes[i] == 0, bytes[i + 1] == 0, bytes[i + 2] == 0, bytes[i + 3] == 1 {
                sc = 4
            }
            if sc > 0 {
                let nalStart = i + sc
                var j = nalStart
                while j + 3 < bytes.count {
                    if bytes[j] == 0, bytes[j + 1] == 0, bytes[j + 2] == 1 { break }
                    if j + 4 < bytes.count, bytes[j] == 0, bytes[j + 1] == 0, bytes[j + 2] == 0, bytes[j + 3] == 1 {
                        break
                    }
                    j += 1
                }
                if j + 3 >= bytes.count { j = bytes.count }
                let len = j - nalStart
                if len > 0 {
                    nals.append((nalStart, len))
                }
                i = j
            } else {
                i += 1
            }
        }

        guard !nals.isEmpty else { return data }
        var out = Data()
        out.reserveCapacity(data.count + nals.count * 4)
        for (start, len) in nals {
            out.append(UInt8((len >> 24) & 0xff))
            out.append(UInt8((len >> 16) & 0xff))
            out.append(UInt8((len >> 8) & 0xff))
            out.append(UInt8(len & 0xff))
            out.append(contentsOf: bytes[start..<(start + len)])
        }
        return out
    }
}
