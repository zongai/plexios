import Foundation

#if NATIVE_FFMPEG
import PlexFFmpeg
#endif

/// FFmpeg-backed demuxer using `PlexFFmpeg` C bridge + libavformat XCFrameworks.
actor FFmpegDemuxer: Demuxer {
    private(set) var isOpen = false
    private(set) var streams: [DemuxStreamInfo] = []
    private(set) var durationMs: Int64?
    private(set) var formatName: String?

    #if NATIVE_FFMPEG
    nonisolated(unsafe) private var ctx: OpaquePointer?
    #endif

    func open(url: URL, headers: [String: String]) async throws {
        await close()
        #if NATIVE_FFMPEG
        let headerString = headers
            .map { "\($0.key): \($0.value)\r\n" }
            .joined()
        let urlString = url.absoluteString
        let opened = urlString.withCString { urlPtr -> OpaquePointer? in
            if headerString.isEmpty {
                return plex_ff_open(urlPtr, nil)
            }
            return headerString.withCString { hPtr in
                plex_ff_open(urlPtr, hPtr)
            }
        }
        guard let opened else {
            throw DemuxError.openFailed("plex_ff_open failed for \(url.absoluteString)")
        }
        ctx = opened
        isOpen = true
        if let namePtr = plex_ff_format_name(opened) {
            formatName = String(cString: namePtr)
        }
        let dur = plex_ff_duration_ms(opened)
        if dur >= 0 { durationMs = dur }

        let count = Int(plex_ff_stream_count(opened))
        var list: [DemuxStreamInfo] = []
        for i in 0..<count {
            var info = PlexFFStreamInfo()
            guard plex_ff_stream_info(opened, Int32(i), &info) == 0 else { continue }
            let kind: MediaPacket.Kind
            switch info.media_type {
            case 1: kind = .video
            case 2: kind = .audio
            case 3: kind = .subtitle
            default: kind = .unknown
            }
            let codec = withUnsafeBytes(of: info.codec_name) { raw -> String in
                let ptr = raw.bindMemory(to: CChar.self).baseAddress!
                return String(cString: ptr)
            }
            var extradata: Data?
            #if NATIVE_FFMPEG
            let need = plex_ff_stream_extradata(opened, Int32(i), nil, 0)
            if need > 0 {
                var buf = [UInt8](repeating: 0, count: Int(need))
                let written = buf.withUnsafeMutableBufferPointer { ptr in
                    plex_ff_stream_extradata(opened, Int32(i), ptr.baseAddress, Int32(need))
                }
                if written > 0 {
                    extradata = Data(buf.prefix(Int(written)))
                }
            }
            #endif
            list.append(DemuxStreamInfo(
                index: Int(info.index),
                kind: kind,
                codecName: codec.isEmpty ? nil : codec,
                codecTag: nil,
                width: info.width > 0 ? Int(info.width) : nil,
                height: info.height > 0 ? Int(info.height) : nil,
                sampleRate: info.sample_rate > 0 ? Int(info.sample_rate) : nil,
                channels: info.channels > 0 ? Int(info.channels) : nil,
                language: nil,
                bitrate: info.bitrate > 0 ? Int(info.bitrate) : nil,
                extradata: extradata
            ))
        }
        streams = list
        #else
        throw DemuxError.ffmpegNotLinked
        #endif
    }

    func close() async {
        #if NATIVE_FFMPEG
        if let ctx {
            plex_ff_close(ctx)
        }
        ctx = nil
        #endif
        isOpen = false
        streams = []
        durationMs = nil
        formatName = nil
    }

    func nextPacket() async throws -> MediaPacket? {
        #if NATIVE_FFMPEG
        guard let ctx else { throw DemuxError.notOpen }
        var pkt = PlexFFPacket()
        let rc = plex_ff_read(ctx, &pkt)
        if rc == 1 { return nil }
        if rc != 0 {
            throw DemuxError.readFailed("plex_ff_read \(rc)")
        }
        defer { plex_ff_packet_free(&pkt) }
        let kind: MediaPacket.Kind
        switch pkt.media_type {
        case 1: kind = .video
        case 2: kind = .audio
        case 3: kind = .subtitle
        default: kind = .unknown
        }
        let data: Data
        if let ptr = pkt.data, pkt.size > 0 {
            data = Data(bytes: ptr, count: Int(pkt.size))
        } else {
            data = Data()
        }
        return MediaPacket(
            kind: kind,
            streamIndex: Int(pkt.stream_index),
            data: data,
            ptsMs: pkt.pts_ms >= 0 ? pkt.pts_ms : nil,
            dtsMs: pkt.dts_ms >= 0 ? pkt.dts_ms : nil,
            durationMs: pkt.duration_ms >= 0 ? pkt.duration_ms : nil,
            isKeyFrame: pkt.is_keyframe != 0
        )
        #else
        throw DemuxError.ffmpegNotLinked
        #endif
    }

    func seek(toMs ms: Int64) async throws {
        #if NATIVE_FFMPEG
        guard let ctx else { throw DemuxError.notOpen }
        let rc = plex_ff_seek_ms(ctx, ms)
        if rc != 0 { throw DemuxError.seekFailed }
        #else
        throw DemuxError.ffmpegNotLinked
        #endif
    }
}
