import Foundation

/// Phase 2: combines Plex metadata with network container probe (HTTP Range).
/// FFmpeg full probe activates when `NATIVE_FFMPEG` is linked.
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
            videoTracks: videoStreams.map { s in
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

    /// Probe media URL with HTTP Range + container sniffers; merge onto Plex metadata baseline.
    func probeURL(
        _ url: URL,
        headers: [String: String] = [:],
        baseline: MediaInfo? = nil
    ) async -> MediaInfo {
        var info = baseline ?? MediaInfo(
            container: ContainerInfo(format: nil, formatLongName: nil),
            durationMs: nil,
            bitrate: nil,
            seekable: true,
            videoTracks: [],
            audioTracks: [],
            subtitleTracks: []
        )

        let demuxer = BuiltinContainerDemuxer()
        do {
            try await demuxer.open(url: url, headers: headers)
            if let name = await demuxer.formatName {
                info.container = ContainerInfo(format: name, formatLongName: name)
            }
            if let dur = await demuxer.durationMs {
                info.durationMs = dur
            }
            let demuxStreams = await demuxer.streams
            if !demuxStreams.isEmpty {
                info.videoTracks = demuxStreams.filter { $0.kind == .video }.map {
                    VideoTrackInfo(
                        id: $0.index, codec: $0.codecName, profile: nil, level: nil,
                        width: $0.width, height: $0.height, frameRate: nil, bitDepth: nil,
                        pixelFormat: nil, isHDR: false, colorPrimaries: nil, transfer: nil, matrix: nil
                    )
                }
                info.audioTracks = demuxStreams.filter { $0.kind == .audio }.map {
                    AudioTrackInfo(
                        id: $0.index, codec: $0.codecName, sampleRate: $0.sampleRate,
                        channels: $0.channels, channelLayout: nil, bitrate: $0.bitrate,
                        bitDepth: nil, language: $0.language
                    )
                }
            }
            await demuxer.close()
        } catch {
            // Keep baseline; network probe is best-effort
        }

        return info
    }

    /// Build Plex part Direct Play URL and probe.
    func probePlexPart(
        metadata: PlexMetadata,
        context: ServerContext,
        mediaIndex: Int = 0,
        partIndex: Int = 0
    ) async -> MediaInfo? {
        guard let media = metadata.media[safe: mediaIndex],
              let part = media.parts[safe: partIndex]
        else { return nil }

        let baseline = probeFromPlexMetadata(metadata, mediaIndex: mediaIndex, partIndex: partIndex)
        guard let url = Self.partURL(part: part, baseURL: context.baseURL, token: context.token) else {
            return baseline
        }
        let headers = ["X-Plex-Token": context.token, "Accept": "*/*"]
        return await probeURL(url, headers: headers, baseline: baseline)
    }

    private static func partURL(part: PlexPart, baseURL: URL, token: String) -> URL? {
        let path = part.key.hasPrefix("/") ? String(part.key.dropFirst()) : part.key
        guard let url = PlexURL.join(baseURL, path: path) else { return nil }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
        return components?.url
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
