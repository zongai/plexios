import Foundation

enum PlaybackMode: String, Sendable, Equatable {
    case directPlay
    case directStream
    case transcode
}

struct PlaybackDecision: Sendable, Equatable {
    let mode: PlaybackMode
    let reason: String
    let mediaIndex: Int
    let partIndex: Int
    let selectedAudioStreamId: Int?
    let selectedSubtitleStreamId: Int? // nil = off
    let burnInSubtitles: Bool
    /// Quality cap applied (kbps), if any
    let maxBitrateKbps: Int?

    var isDirectPlay: Bool { mode == .directPlay }
}

struct PlaybackDecisionEngine: Sendable {
    let capabilities: IOSCapabilities
    let preferences: PlaybackPreferences

    init(
        capabilities: IOSCapabilities = .current,
        preferences: PlaybackPreferences = .default
    ) {
        self.capabilities = capabilities
        self.preferences = preferences
    }

    func decide(
        metadata: PlexMetadata,
        network: NetworkClass,
        mediaIndex: Int = 0,
        partIndex: Int = 0,
        forcedAudioId: Int? = nil,
        forcedSubtitleId: Int? = nil
    ) -> PlaybackDecision {
        guard !metadata.media.isEmpty else {
            return PlaybackDecision(
                mode: .transcode,
                reason: "No media versions available",
                mediaIndex: 0,
                partIndex: 0,
                selectedAudioStreamId: nil,
                selectedSubtitleStreamId: nil,
                burnInSubtitles: false,
                maxBitrateKbps: preferences.maxVideoBitrateKbps
            )
        }

        let mi = min(mediaIndex, metadata.media.count - 1)
        let media = metadata.media[mi]
        let parts = media.parts
        guard !parts.isEmpty else {
            return PlaybackDecision(
                mode: .transcode,
                reason: "Media has no parts",
                mediaIndex: mi,
                partIndex: 0,
                selectedAudioStreamId: nil,
                selectedSubtitleStreamId: nil,
                burnInSubtitles: false,
                maxBitrateKbps: preferences.maxVideoBitrateKbps
            )
        }
        let pi = min(partIndex, parts.count - 1)
        let part = parts[pi]
        let streams = part.streams

        let video = streams.first { $0.streamType == .video }
        let audioStreams = streams.filter { $0.streamType == .audio }
        let subtitleStreams = streams.filter { $0.streamType == .subtitle }

        let audioId = selectAudio(audioStreams, forced: forcedAudioId)
        let selectedAudio = audioStreams.first { $0.id == audioId }
        let (subtitleId, burnIn) = selectSubtitle(subtitleStreams, forced: forcedSubtitleId)

        let container = (part.container ?? media.container)?.lowercased()
        let videoCodec = (video?.codec ?? media.videoCodec)?.lowercased()
        let audioCodec = (selectedAudio?.codec ?? media.audioCodec)?.lowercased()

        // User bitrate cap forces transcode when below source
        if let maxBr = preferences.maxVideoBitrateKbps,
           let sourceBr = media.bitrate,
           sourceBr > maxBr {
            return PlaybackDecision(
                mode: .transcode,
                reason: "Quality limited to \(maxBr) kbps (source \(sourceBr) kbps)",
                mediaIndex: mi,
                partIndex: pi,
                selectedAudioStreamId: audioId,
                selectedSubtitleStreamId: subtitleId,
                burnInSubtitles: burnIn || (subtitleId != nil && !canNativeSub(subtitleStreams, id: subtitleId)),
                maxBitrateKbps: maxBr
            )
        }

        // Relay: prefer lower bitrate / allow transcode more readily
        let effectiveMax: Int? = {
            if network == .relay {
                return min(preferences.maxVideoBitrateKbps ?? 2000, 2000)
            }
            return preferences.maxVideoBitrateKbps
        }()

        let normalizedVideo = IOSCapabilities.normalizeVideoCodec(videoCodec)
        let videoOK = capabilities.supportsVideoCodec(videoCodec)
        let audioOK = capabilities.supportsAudioCodec(audioCodec)
        let containerOK = capabilities.supportsContainer(container)

        // Subtitle path
        var needBurnIn = burnIn
        if let sid = subtitleId, !canNativeSub(subtitleStreams, id: sid) {
            needBurnIn = true
        }
        // External soft-subs cannot be attached on pure Direct Play file URLs — remux/HLS
        let externalSoftSub: Bool = {
            guard let sid = subtitleId,
                  let stream = subtitleStreams.first(where: { $0.id == sid }),
                  stream.isExternal, !needBurnIn
            else { return false }
            return true
        }()

        // Soft subtitles: prefer HLS packaging (segmented VTT) over pure Direct Play so
        // AVPlayer always receives a legible media group. Pure file Direct Play often
        // has no selectable text track for external WEBVTT/SRT.
        let softSubSelected = subtitleId != nil && !needBurnIn

        // Direct Play (native container + codecs, no burn-in, no soft-sub packaging need)
        if containerOK && videoOK && audioOK && !needBurnIn && !externalSoftSub && !softSubSelected {
            return PlaybackDecision(
                mode: .directPlay,
                reason: "Container, video (\(normalizedVideo ?? videoCodec ?? "?")), and audio (\(audioCodec ?? "?")) supported natively",
                mediaIndex: mi,
                partIndex: pi,
                selectedAudioStreamId: audioId,
                selectedSubtitleStreamId: subtitleId,
                burnInSubtitles: false,
                maxBitrateKbps: effectiveMax
            )
        }

        // Direct Stream — video+audio OK, container remap / external soft-sub via HLS
        if videoOK && audioOK && !needBurnIn {
            var reasons: [String] = []
            if !containerOK {
                reasons.append("container \(container ?? "?") remux required")
            }
            if externalSoftSub {
                reasons.append("external subtitle packaged in stream")
            }
            if reasons.isEmpty { reasons.append("direct stream remux") }
            return PlaybackDecision(
                mode: .directStream,
                reason: reasons.joined(separator: "; "),
                mediaIndex: mi,
                partIndex: pi,
                selectedAudioStreamId: audioId,
                selectedSubtitleStreamId: subtitleId,
                burnInSubtitles: false,
                maxBitrateKbps: effectiveMax
            )
        }

        // Transcode
        var reasons: [String] = []
        if !videoOK { reasons.append("video codec \(videoCodec ?? "?") unsupported") }
        if !audioOK { reasons.append("audio codec \(audioCodec ?? "?") unsupported") }
        if needBurnIn { reasons.append("subtitle burn-in required") }
        if reasons.isEmpty { reasons.append("transcode required") }

        return PlaybackDecision(
            mode: .transcode,
            reason: reasons.joined(separator: "; "),
            mediaIndex: mi,
            partIndex: pi,
            selectedAudioStreamId: audioId,
            selectedSubtitleStreamId: subtitleId,
            burnInSubtitles: needBurnIn,
            maxBitrateKbps: effectiveMax
        )
    }

    // MARK: - Stream selection

    private func selectAudio(_ streams: [PlexStream], forced: Int?) -> Int? {
        if let forced, streams.contains(where: { $0.id == forced }) { return forced }
        if let pref = preferences.preferredAudioLanguage {
            if let match = streams.first(where: {
                $0.languageCode?.lowercased() == pref.lowercased()
                    || $0.language?.lowercased() == pref.lowercased()
            }) { return match.id }
        }
        if let selected = streams.first(where: \.isSelected) { return selected.id }
        if let def = streams.first(where: \.isDefault) { return def.id }
        return streams.first?.id
    }

    private func selectSubtitle(_ streams: [PlexStream], forced: Int?) -> (Int?, Bool) {
        if !preferences.subtitlesEnabled {
            return (nil, false)
        }
        if let forced {
            if forced < 0 { return (nil, false) }
            if let stream = streams.first(where: { $0.id == forced }) {
                return (forced, capabilities.requiresBurnIn(stream))
            }
        }
        if let pref = preferences.preferredSubtitleLanguage {
            if let match = streams.first(where: {
                $0.languageCode?.lowercased() == pref.lowercased()
                    || $0.language?.lowercased() == pref.lowercased()
            }) {
                return (match.id, capabilities.requiresBurnIn(match))
            }
        }
        if let forcedTrack = streams.first(where: \.isForced) {
            return (forcedTrack.id, capabilities.requiresBurnIn(forcedTrack))
        }
        if let selected = streams.first(where: \.isSelected) {
            return (selected.id, capabilities.requiresBurnIn(selected))
        }
        // Prefer a soft (text) track when subtitles are enabled — previously
        // returned nil unless PMS marked a track selected/forced (WEBVTT/SRT silent).
        if let text = streams.first(where: {
            capabilities.supportsSubtitleNatively($0) && !capabilities.requiresBurnIn($0)
        }) {
            return (text.id, false)
        }
        if let any = streams.first {
            return (any.id, capabilities.requiresBurnIn(any))
        }
        return (nil, false)
    }

    private func canNativeSub(_ streams: [PlexStream], id: Int?) -> Bool {
        guard let id, let stream = streams.first(where: { $0.id == id }) else { return true }
        return capabilities.supportsSubtitleNatively(stream) && !capabilities.requiresBurnIn(stream)
    }
}
