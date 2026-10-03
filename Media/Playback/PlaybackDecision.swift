import Foundation

enum PlaybackMode: String, Sendable, Equatable {
    case directPlay
    case directStream
    case transcode
}

/// Contract: system (AVPlayer/Exo/MF) vs vlc fallback.
enum PlaybackBackend: String, Sendable, Equatable {
    case system
    case vlc
}

struct PlaybackDecision: Sendable, Equatable {
    let mode: PlaybackMode
    let reason: String
    /// Contract: system (AVPlayer) vs vlc fallback. Actual final backend may still switch at runtime.
    let backend: PlaybackBackend
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

    /// Whether VLC may be chosen as capability-gap fallback.
    private var vlcFallbackAvailable: Bool {
        preferences.allowVLCPlayer
            && !preferences.preferSystemPlayer
            && VLCPlaybackBackend.isLinked
    }

    init(
        capabilities: IOSCapabilities = .current,
        preferences: PlaybackPreferences = .default
    ) {
        self.capabilities = capabilities
        self.preferences = preferences
    }

    /// Builds an engine; Decision selects system vs VLC matrix per media.
    static func make(preferences: PlaybackPreferences) -> PlaybackDecisionEngine {
        PlaybackDecisionEngine(
            capabilities: .avPlayerProfile,
            preferences: preferences
        )
    }

    func decide(
        metadata: PlexMetadata,
        network: NetworkClass,
        mediaIndex: Int = 0,
        partIndex: Int = 0,
        forcedAudioId: Int? = nil,
        forcedSubtitleId: Int? = nil
    ) -> PlaybackDecision {
        // Contract: system matrix first; VLC only on capability gap (not bitrate caps).
        let system = evaluate(
            metadata: metadata,
            network: network,
            mediaIndex: mediaIndex,
            partIndex: partIndex,
            forcedAudioId: forcedAudioId,
            forcedSubtitleId: forcedSubtitleId,
            caps: .avPlayerProfile,
            backend: .system
        )
        if preferences.preferSystemPlayer {
            return system
        }
        // Bitrate-limited transcode cannot be fixed by switching backend
        if system.mode == .transcode, system.reason.hasPrefix("Quality limited") {
            return system
        }
        if system.mode != .transcode {
            return system
        }
        guard vlcFallbackAvailable else { return system }

        let vlc = evaluate(
            metadata: metadata,
            network: network,
            mediaIndex: mediaIndex,
            partIndex: partIndex,
            forcedAudioId: forcedAudioId,
            forcedSubtitleId: forcedSubtitleId,
            caps: .vlcProfile,
            backend: .vlc
        )
        if vlc.mode == .directPlay || vlc.mode == .directStream {
            return vlc
        }
        // Keep system transcode decision (server-side) when VLC also cannot DP/DS
        return system
    }

    /// Evaluate one capability matrix for a fixed backend.
    private func evaluate(
        metadata: PlexMetadata,
        network: NetworkClass,
        mediaIndex: Int,
        partIndex: Int,
        forcedAudioId: Int?,
        forcedSubtitleId: Int?,
        caps: IOSCapabilities,
        backend: PlaybackBackend
    ) -> PlaybackDecision {
        guard !metadata.media.isEmpty else {
            return PlaybackDecision(
                mode: .transcode,
                reason: "No media versions available",
                backend: backend,
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
                backend: backend,
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
        let (subtitleId, burnIn) = selectSubtitle(subtitleStreams, forced: forcedSubtitleId, caps: caps)

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
                backend: backend,
                mediaIndex: mi,
                partIndex: pi,
                selectedAudioStreamId: audioId,
                selectedSubtitleStreamId: subtitleId,
                burnInSubtitles: burnIn || (subtitleId != nil && !canNativeSub(subtitleStreams, id: subtitleId, caps: caps)),
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
        let videoOK = caps.supportsVideoCodec(videoCodec)
        let audioOK = caps.supportsAudioCodec(audioCodec)
        let containerOK = caps.supportsContainer(container)

        // Subtitle path
        var needBurnIn = burnIn
        if let sid = subtitleId, !canNativeSub(subtitleStreams, id: sid, caps: caps) {
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

        // Direct Play (native container + codecs, no burn-in)
        // VLC profile can soft-render external/text subs without HLS remux.
        let vlcSoftOK = caps.isVLCProfile && !needBurnIn
        if containerOK && videoOK && audioOK && !needBurnIn
            && (vlcSoftOK || (!externalSoftSub && !softSubSelected)) {
            let via = caps.isVLCProfile ? "VLC" : "AVPlayer"
            return PlaybackDecision(
                mode: .directPlay,
                reason: "Direct Play via \(via): \(container ?? "?") / \(normalizedVideo ?? videoCodec ?? "?") / \(audioCodec ?? "?")",
                backend: backend,
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
                backend: backend,
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
            backend: backend,
            mediaIndex: mi,
            partIndex: pi,
            selectedAudioStreamId: audioId,
            selectedSubtitleStreamId: subtitleId,
            burnInSubtitles: needBurnIn,
            maxBitrateKbps: effectiveMax
        )
    }

    // MARK: - Stream selection

    private func matchesLanguage(_ stream: PlexStream, pref: String) -> Bool {
        let p = pref.lowercased()
        guard !p.isEmpty else { return false }
        let code = (stream.languageCode ?? "").lowercased()
        let name = (stream.language ?? "").lowercased()
        if code == p || name == p { return true }
        // Prefix match: "zh" matches "zh-cn", "zh-hans", "chi"
        if !code.isEmpty, code.hasPrefix(p) || p.hasPrefix(code) { return true }
        // Common aliases
        let aliases: [String: [String]] = [
            "zh": ["chi", "zho", "zh-cn", "zh-tw", "zh-hans", "zh-hant", "chinese"],
            "zh-cn": ["zh", "chi", "zh-hans", "cmn"],
            "zh-tw": ["zh", "chi", "zh-hant", "cht"],
            "en": ["eng", "english"],
            "ja": ["jpn", "japanese"],
            "ko": ["kor", "korean"],
            "es": ["spa", "spanish"],
            "fr": ["fre", "fra", "french"],
            "de": ["ger", "deu", "german"],
            "pt": ["por", "portuguese"],
            "ru": ["rus", "russian"],
        ]
        if let list = aliases[p] {
            if list.contains(code) || list.contains(name) { return true }
            if list.contains(where: { code.hasPrefix($0) || name.contains($0) }) { return true }
        }
        return name.contains(p)
    }

    private func selectAudio(_ streams: [PlexStream], forced: Int?) -> Int? {
        if let forced, streams.contains(where: { $0.id == forced }) { return forced }
        // 1) User priority list
        for pref in preferences.preferredAudioLanguages where !pref.isEmpty {
            if let match = streams.first(where: { matchesLanguage($0, pref: pref) }) {
                return match.id
            }
        }
        // 2) Video / server default
        if let selected = streams.first(where: \.isSelected) { return selected.id }
        if let def = streams.first(where: \.isDefault) { return def.id }
        return streams.first?.id
    }

    private func selectSubtitle(_ streams: [PlexStream], forced: Int?, caps: IOSCapabilities) -> (Int?, Bool) {
        // Explicit user pick (or off) always wins — even if global subtitles toggle is off.
        if let forced {
            if forced < 0 { return (nil, false) }
            if let stream = streams.first(where: { $0.id == forced }) {
                return (forced, caps.requiresBurnIn(stream))
            }
        }
        if !preferences.subtitlesEnabled {
            return (nil, false)
        }
        // 1) User priority list
        for pref in preferences.preferredSubtitleLanguages where !pref.isEmpty {
            if let match = streams.first(where: { matchesLanguage($0, pref: pref) }) {
                return (match.id, caps.requiresBurnIn(match))
            }
        }
        // 2) Video / server default (selected or default flag from PMS)
        if let selected = streams.first(where: \.isSelected) {
            return (selected.id, caps.requiresBurnIn(selected))
        }
        if let def = streams.first(where: \.isDefault) {
            return (def.id, caps.requiresBurnIn(def))
        }
        // 3) Only when user did not set a language list: mild heuristics
        if preferences.preferredSubtitleLanguages.isEmpty {
            if let forcedTrack = streams.first(where: \.isForced) {
                return (forcedTrack.id, caps.requiresBurnIn(forcedTrack))
            }
            if let text = streams.first(where: {
                caps.supportsSubtitleNatively($0) && !caps.requiresBurnIn($0)
            }) {
                return (text.id, false)
            }
        }
        // Preferences set but no match and no server default → leave off
        return (nil, false)
    }

    private func canNativeSub(_ streams: [PlexStream], id: Int?, caps: IOSCapabilities) -> Bool {
        guard let id, let stream = streams.first(where: { $0.id == id }) else { return true }
        return caps.supportsSubtitleNatively(stream) && !caps.requiresBurnIn(stream)
    }
}
