import AudioToolbox
import AVFoundation
import Foundation

/// Decodes compressed audio to PCM using AudioToolbox / AVAudioConverter where available.
final class SystemAudioDecoder: AudioDecoder {
    let codec: AudioCodecID
    private(set) var isReady = false

    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?
    private var config: AudioDecoderConfig?
    private var packetCount: UInt32 = 0

    // AudioToolbox queue for formats that need AudioFileStream / AudioConverter
    private var audioConverter: AudioConverterRef?
    private var asbdIn = AudioStreamBasicDescription()
    private var asbdOut = AudioStreamBasicDescription()

    init(codec: AudioCodecID) {
        self.codec = codec
    }

    deinit { invalidate() }

    func setup(config: AudioDecoderConfig) throws {
        invalidate()
        self.config = config
        guard config.codec == codec else {
            throw AudioDecoderError.unsupportedCodec("config mismatch")
        }

        let rate = Double(max(config.sampleRate, 8000))
        let channels = max(config.channels, 1)

        // Output: interleaved Float32 PCM
        guard let outFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: rate,
            channels: AVAudioChannelCount(channels),
            interleaved: true
        ) else {
            throw AudioDecoderError.setupFailed("output format")
        }
        outputFormat = outFormat

        if codec == .pcm {
            isReady = true
            return
        }

        // Prefer AVAudioFormat for AAC
        if codec == .aac {
            if let inFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: rate,
                channels: AVAudioChannelCount(channels),
                interleaved: true
            ) {
                // Compressed input uses magic cookie / converter from packets via AudioConverter below
                _ = inFormat
            }
            try setupAudioConverter(sampleRate: rate, channels: channels, formatID: kAudioFormatMPEG4AAC)
            isReady = true
            return
        }

        let formatID: AudioFormatID
        switch codec {
        case .mp3: formatID = kAudioFormatMPEGLayer3
        case .flac: formatID = kAudioFormatFLAC
        case .alac: formatID = kAudioFormatAppleLossless
        case .ac3: formatID = kAudioFormatAC3
        case .eac3: formatID = kAudioFormatEnhancedAC3
        default:
            throw AudioDecoderError.unsupportedCodec(codec.rawValue)
        }

        try setupAudioConverter(sampleRate: rate, channels: channels, formatID: formatID)
        isReady = true
    }

    func decode(packet: MediaPacket) throws -> [AudioFrame] {
        guard isReady, let config, let outFormat = outputFormat else {
            throw AudioDecoderError.notReady
        }
        guard packet.kind == .audio, !packet.data.isEmpty else { return [] }

        if codec == .pcm {
            return [pcmFrame(from: packet, config: config, outFormat: outFormat)]
        }

        guard let audioConverter else {
            throw AudioDecoderError.notReady
        }

        // Input packet buffer
        var inputData = packet.data
        let inputSize = UInt32(inputData.count)
        var packetsConsumed: UInt32 = 1

        let maxOutFrames = UInt32(max(outFormat.sampleRate * 0.1, 1024)) // ~100ms
        let outBytes = Int(maxOutFrames) * Int(outFormat.channelCount) * MemoryLayout<Float>.size
        var outData = Data(count: outBytes)

        var status: OSStatus = noErr
        let framesWritten: UInt32 = outData.withUnsafeMutableBytes { outRaw in
            inputData.withUnsafeMutableBytes { inRaw in
                guard let inBase = inRaw.baseAddress,
                      let outBase = outRaw.baseAddress else { return 0 }

                var inBuffer = AudioBuffer(
                    mNumberChannels: UInt32(config.channels),
                    mDataByteSize: inputSize,
                    mData: inBase
                )
                var inBufList = AudioBufferList(mNumberBuffers: 1, mBuffers: inBuffer)
                var inPacketDesc = AudioStreamPacketDescription(
                    mStartOffset: 0,
                    mVariableFramesInPacket: 0,
                    mDataByteSize: inputSize
                )

                var outBuffer = AudioBuffer(
                    mNumberChannels: outFormat.channelCount,
                    mDataByteSize: UInt32(outBytes),
                    mData: outBase
                )
                var outBufList = AudioBufferList(mNumberBuffers: 1, mBuffers: outBuffer)

                var ioOutPackets = maxOutFrames

                // Provide input via callback
                struct Ctx {
                    var data: UnsafeMutableRawPointer
                    var size: UInt32
                    var done: Bool
                    var desc: AudioStreamPacketDescription
                }
                var ctx = Ctx(data: inBase, size: inputSize, done: false, desc: inPacketDesc)

                let callback: AudioConverterComplexInputDataProc = { _, ioNumDataPackets, ioData, outDesc, user in
                    let c = user!.assumingMemoryBound(to: Ctx.self)
                    if c.pointee.done {
                        ioNumDataPackets.pointee = 0
                        return noErr
                    }
                    ioNumDataPackets.pointee = 1
                    let abl = UnsafeMutableAudioBufferListPointer(ioData)
                    abl[0].mData = c.pointee.data
                    abl[0].mDataByteSize = c.pointee.size
                    abl[0].mNumberChannels = 1
                    if let outDesc {
                        outDesc.pointee = UnsafeMutablePointer<AudioStreamPacketDescription>.allocate(capacity: 1)
                        outDesc.pointee?[0] = c.pointee.desc
                    }
                    c.pointee.done = true
                    return noErr
                }

                status = AudioConverterFillComplexBuffer(
                    audioConverter,
                    callback,
                    &ctx,
                    &ioOutPackets,
                    &outBufList,
                    nil
                )
                _ = packetsConsumed
                return ioOutPackets
            }
        }

        if status != noErr && status != kAudioConverterErr_InvalidInputSize {
            // Soft-fail empty
            if framesWritten == 0 {
                throw AudioDecoderError.decodeFailed("AudioConverter \(status)")
            }
        }

        let byteCount = Int(framesWritten) * Int(outFormat.channelCount) * MemoryLayout<Float>.size
        guard byteCount > 0 else { return [] }
        let pcm = outData.prefix(byteCount)
        return [
            AudioFrame(
                pcm: Data(pcm),
                sampleRate: outFormat.sampleRate,
                channelCount: Int(outFormat.channelCount),
                frameCount: Int(framesWritten),
                ptsMs: packet.ptsMs
            )
        ]
    }

    func flush() {
        if let audioConverter {
            AudioConverterReset(audioConverter)
        }
    }

    func invalidate() {
        flush()
        if let audioConverter {
            AudioConverterDispose(audioConverter)
        }
        audioConverter = nil
        converter = nil
        isReady = false
    }

    // MARK: - Helpers

    private func setupAudioConverter(sampleRate: Double, channels: Int, formatID: AudioFormatID) throws {
        asbdIn = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: formatID,
            mFormatFlags: 0,
            mBytesPerPacket: 0,
            mFramesPerPacket: formatID == kAudioFormatMPEG4AAC ? 1024 : 0,
            mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 0,
            mReserved: 0
        )
        asbdOut = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(MemoryLayout<Float>.size * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(MemoryLayout<Float>.size * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var converter: AudioConverterRef?
        let status = AudioConverterNew(&asbdIn, &asbdOut, &converter)
        guard status == noErr, let converter else {
            throw AudioDecoderError.setupFailed("AudioConverterNew \(status)")
        }

        if let cookie = config?.extradata, !cookie.isEmpty {
            cookie.withUnsafeBytes { raw in
                if let base = raw.baseAddress {
                    var size = UInt32(cookie.count)
                    AudioConverterSetProperty(
                        converter,
                        kAudioConverterDecompressionMagicCookie,
                        size,
                        base
                    )
                }
            }
        }
        audioConverter = converter
    }

    private func pcmFrame(from packet: MediaPacket, config: AudioDecoderConfig, outFormat: AVAudioFormat) -> AudioFrame {
        // Assume Float32 interleaved already, or convert S16
        let data: Data
        if config.bitDepth == 16 {
            let samples = packet.data.count / 2
            var floats = [Float](repeating: 0, count: samples)
            packet.data.withUnsafeBytes { raw in
                let s16 = raw.bindMemory(to: Int16.self)
                for i in 0..<samples {
                    floats[i] = Float(s16[i]) / Float(Int16.max)
                }
            }
            data = floats.withUnsafeBufferPointer { Data(buffer: $0) }
            return AudioFrame(
                pcm: data,
                sampleRate: outFormat.sampleRate,
                channelCount: Int(outFormat.channelCount),
                frameCount: samples / max(Int(outFormat.channelCount), 1),
                ptsMs: packet.ptsMs
            )
        }
        return AudioFrame(
            pcm: packet.data,
            sampleRate: outFormat.sampleRate,
            channelCount: Int(outFormat.channelCount),
            frameCount: packet.data.count / (MemoryLayout<Float>.size * max(Int(outFormat.channelCount), 1)),
            ptsMs: packet.ptsMs
        )
    }
}
