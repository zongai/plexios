import Foundation

/// Builds Direct Play and Universal Transcoder URLs.
struct PlaybackURLBuilder: Sendable {
    let baseURL: URL
    let token: String
    let clientIdentifier: String
    let identityHeaders: [String: String]

    func directPlayURL(part: PlexPart) -> URL? {
        // part.key is typically "/library/parts/{id}/{n}/file.mkv"
        var url = baseURL
        let path = part.key.hasPrefix("/") ? String(part.key.dropFirst()) : part.key
        for segment in path.split(separator: "/") {
            url = url.appendingPathComponent(String(segment))
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier)
        ]
        components?.queryItems = items
        return components?.url
    }

    func universalStartURL(
        metadataKey: String,
        decision: PlaybackDecision,
        sessionId: String,
        offsetMs: Int64,
        network: NetworkClass
    ) -> URL? {
        var components = URLComponents(
            url: PlexURL.join(baseURL, path: "video/:/transcode/universal/start.m3u8") ?? baseURL,
            resolvingAgainstBaseURL: false
        )

        let directPlay = decision.mode == .directPlay ? "1" : "0"
        // Direct Stream only when we explicitly remux; full transcode must disable both
        let directStream = decision.mode == .directStream ? "1" : "0"
        // Only pass through audio when Direct Play / Direct Stream and audio is native-safe
        let directStreamAudio = (decision.mode == .directPlay || decision.mode == .directStream) ? "1" : "0"

        let caps = IOSCapabilities.current
        var items: [URLQueryItem] = [
            URLQueryItem(name: "path", value: metadataKey),
            URLQueryItem(name: "mediaIndex", value: "\(decision.mediaIndex)"),
            URLQueryItem(name: "partIndex", value: "\(decision.partIndex)"),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: directPlay),
            URLQueryItem(name: "directStream", value: directStream),
            URLQueryItem(name: "directStreamAudio", value: directStreamAudio),
            // Only codecs AVPlayer can decode — never VP9/OPUS
            URLQueryItem(name: "videoCodecs", value: caps.videoCodecsQueryValue),
            URLQueryItem(name: "audioCodecs", value: caps.audioCodecsQueryValue),
            URLQueryItem(name: "subtitleCodecs", value: caps.subtitleCodecsQueryValue),
            URLQueryItem(name: "session", value: sessionId),
            URLQueryItem(name: "offset", value: "\(offsetMs)"),
            URLQueryItem(name: "copyts", value: "1"),
            URLQueryItem(name: "location", value: network == .lan ? "lan" : "wan"),
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier),
            URLQueryItem(name: "X-Plex-Product", value: identityHeaders["X-Plex-Product"] ?? "Plex iOS Native"),
            URLQueryItem(name: "X-Plex-Platform", value: "iOS")
        ]

        if let maxBr = decision.maxBitrateKbps {
            items.append(URLQueryItem(name: "maxVideoBitrate", value: "\(maxBr)"))
            items.append(URLQueryItem(name: "videoQuality", value: "100"))
        }

        // Plex universal subtitle modes (see PMS Transcoder API):
        // burn | none | sidecar | embedded | segmented | auto
        // For HLS + AVPlayer, **segmented** yields WebVTT segments AVPlayer can show.
        if decision.burnInSubtitles {
            items.append(URLQueryItem(name: "subtitles", value: "burn"))
            items.append(URLQueryItem(name: "advancedSubtitles", value: "burn"))
        } else if decision.selectedSubtitleStreamId != nil {
            items.append(URLQueryItem(name: "subtitles", value: "segmented"))
            items.append(URLQueryItem(name: "advancedSubtitles", value: "text"))
        } else {
            items.append(URLQueryItem(name: "subtitles", value: "none"))
        }

        if let audioId = decision.selectedAudioStreamId {
            items.append(URLQueryItem(name: "audioStreamID", value: "\(audioId)"))
        }
        if let subId = decision.selectedSubtitleStreamId {
            items.append(URLQueryItem(name: "subtitleStreamID", value: "\(subId)"))
        }

        components?.queryItems = items
        return components?.url
    }

    func playbackURL(
        metadata: PlexMetadata,
        part: PlexPart,
        decision: PlaybackDecision,
        sessionId: String,
        offsetMs: Int64,
        network: NetworkClass
    ) -> URL? {
        switch decision.mode {
        case .directPlay:
            return directPlayURL(part: part)
        case .directStream, .transcode:
            return universalStartURL(
                metadataKey: metadata.key,
                decision: decision,
                sessionId: sessionId,
                offsetMs: offsetMs,
                network: network
            )
        }
    }
}
