import Foundation

/// Phase 2 demuxer **without** FFmpeg: container detection + header probe only.
/// `nextPacket()` is unsupported until NATIVE_FFMPEG builds ship.
actor BuiltinContainerDemuxer: Demuxer {
    private(set) var isOpen = false
    private(set) var streams: [DemuxStreamInfo] = []
    private(set) var durationMs: Int64?
    private(set) var formatName: String?

    private let dataSource = HTTPRangeDataSource()
    private var openURL: URL?

    func open(url: URL, headers: [String: String]) async throws {
        await close()
        openURL = url
        let info = try await dataSource.open(url: url, headers: headers)
        _ = info

        // Sniff container
        let head = try await dataSource.read(offset: 0, length: 64)
        if head.count >= 4,
           head[0] == 0x1A, head[1] == 0x45, head[2] == 0xDF, head[3] == 0xA3 {
            let mkv = try await MKVProbe().probe(dataSource: dataSource)
            formatName = mkv.docType ?? "matroska"
            isOpen = true
            return
        }
        if head.first == 0x47 {
            let ts = try await TSProbe().probe(dataSource: dataSource)
            if ts.isTransportStream {
                formatName = ts.packetSize == 192 ? "m2ts" : "mpegts"
                isOpen = true
                return
            }
        }
        // ISO BMFF
        let mp4 = try await MP4BoxProbe().probe(dataSource: dataSource)
        if mp4.brand != nil || mp4.hasMoov {
            formatName = "mp4"
            durationMs = mp4.durationMs
            var idx = 0
            for c in mp4.videoCodecs {
                streams.append(DemuxStreamInfo(
                    index: idx, kind: .video, codecName: c,
                    codecTag: nil, width: nil, height: nil,
                    sampleRate: nil, channels: nil, language: nil, bitrate: nil, extradata: nil
                ))
                idx += 1
            }
            for c in mp4.audioCodecs {
                streams.append(DemuxStreamInfo(
                    index: idx, kind: .audio, codecName: c,
                    codecTag: nil, width: nil, height: nil,
                    sampleRate: nil, channels: nil, language: nil, bitrate: nil, extradata: nil
                ))
                idx += 1
            }
            isOpen = true
            return
        }

        throw DemuxError.openFailed("Unrecognized container at \(url.lastPathComponent)")
    }

    func close() async {
        isOpen = false
        streams = []
        durationMs = nil
        formatName = nil
        openURL = nil
    }

    func nextPacket() async throws -> MediaPacket? {
        throw DemuxError.ffmpegNotLinked
    }

    func seek(toMs ms: Int64) async throws {
        throw DemuxError.ffmpegNotLinked
    }
}
