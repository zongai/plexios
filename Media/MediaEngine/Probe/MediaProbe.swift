import Foundation

/// Phase 1: derives coarse MediaInfo from Plex metadata only (no FFmpeg).
/// Phase 2 replaces with real demux probe over HTTP Range.
struct MediaProbe: Sendable {
    func probeFromPlexMetadata(
        _ metadata: PlexMetadata,
        mediaIndex: Int = 0,
        partIndex: Int = 0
    ) -> MediaInfo? {
        guard let media = metadata.media[safe: mediaIndex],
              let part = media.parts[safe: partIndex]
        else { return nil }

        let videoStreams = part.streams.filter { $0.streamType == .video }
        let audioStreams = part.streams.filter { $0.streamType == .audio }
        let subStreams = part.streams.filter { $0.streamType == .subtitle }

        return MediaInfo(
            container: ContainerInfo(
                format: part.container ?? media.container,
                formatLongName: nil
            ),
            durationMs: metadata.duration ?? part.duration ?? media.duration,
            bitrate: media.bitrate,
            seekable: true,
            videoTracks: videoStreams.enumerated().map { idx, s in
                VideoTrackInfo(
                    id: s.id,
                    codec: s.codec,
                    profile: nil,
                    level: nil,
                    width: media.width,
                    height: media.height,
                    frameRate: nil,
                    bitDepth: s.bitDepth,
                    pixelFormat: nil,
                    isHDR: false,
                    colorPrimaries: nil,
                    transfer: nil,
                    matrix: nil
                )
            },
            audioTracks: audioStreams.map { s in
                AudioTrackInfo(
                    id: s.id,
                    codec: s.codec,
                    sampleRate: nil,
                    channels: s.channels,
                    channelLayout: nil,
                    bitrate: s.bitrate,
                    bitDepth: s.bitDepth,
                    language: s.languageCode ?? s.language
                )
            },
            subtitleTracks: subStreams.map { s in
                let fmt = (s.format ?? s.codec)?.lowercased() ?? ""
                let bitmap = ["pgs", "vobsub", "dvd_subtitle"].contains(fmt)
                return SubtitleTrackInfo(
                    id: s.id,
                    format: s.format ?? s.codec,
                    language: s.languageCode ?? s.language,
                    isForced: s.isForced,
                    isHearingImpaired: false,
                    isText: !bitmap
                )
            }
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
