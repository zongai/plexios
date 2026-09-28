import Foundation

/// Predicts backend / path from container + codecs. Not a guarantee — runtime fallback still applies.
struct PlaybackCompatibilityAnalyzer: Sendable {
    let capabilities: IOSCapabilities
    /// Feature flag: when false, never recommend native (Phase 1 default).
    let nativeEngineEnabled: Bool

    init(
        capabilities: IOSCapabilities = .current,
        nativeEngineEnabled: Bool = false
    ) {
        self.capabilities = capabilities
        self.nativeEngineEnabled = nativeEngineEnabled
    }

    func analyze(
        metadata: PlexMetadata,
        decision: PlaybackDecision,
        network: NetworkClass
    ) -> CompatibilityReport {
        guard let media = metadata.media[safe: decision.mediaIndex],
              let part = media.parts[safe: decision.partIndex]
        else {
            return CompatibilityReport(
                tracks: TrackCompatibility(
                    container: .unsupported,
                    video: .unsupported,
                    audio: .unsupported,
                    subtitle: .unsupported,
                    hdr: .supported
                ),
                preferredBackend: .avPlayer,
                preferredPath: .plexTranscode,
                reasons: ["Missing media/part"],
                nativeCandidate: false
            )
        }

        let container = (part.container ?? media.container)?.lowercased()
        let videoCodec = media.videoCodec
            ?? part.streams.first(where: { $0.streamType == .video })?.codec
        let audioCodec = media.audioCodec
            ?? part.streams.first(where: { $0.streamType == .audio })?.codec

        let containerLevel = analyzeContainer(container)
        let videoLevel = analyzeVideo(videoCodec)
        let audioLevel = analyzeAudio(audioCodec)
        let subtitleLevel = analyzeSubtitle(
            part.streams.filter { $0.streamType == .subtitle },
            selectedId: decision.selectedSubtitleStreamId,
            burnIn: decision.burnInSubtitles
        )

        var reasons: [String] = []
        if containerLevel == .unsupported {
            reasons.append("container \(container ?? "?") not ideal for AVPlayer Direct Play")
        }
        if videoLevel == .unsupported {
            reasons.append("video \(videoCodec ?? "?") needs transcode or future soft decode")
        }
        if audioLevel == .unsupported {
            reasons.append("audio \(audioCodec ?? "?") needs transcode or soft decode")
        }

        // Phase 1: native never selected for real playback (flag off / stub backend).
        let nativeCandidate = nativeEngineEnabled
            && containerLevel != .unsupported
            && (videoLevel == .hardwareSupported || videoLevel == .softwareSupported)

        let preferredBackend: PlaybackBackend = .avPlayer
        let preferredPath: PlaybackPath = {
            switch decision.mode {
            case .directPlay: return .avPlayerDirect
            case .directStream: return .avPlayerHLS
            case .transcode: return .plexTranscode
            }
        }()

        if decision.mode == .transcode {
            reasons.append("decision engine: \(decision.reason)")
        }

        return CompatibilityReport(
            tracks: TrackCompatibility(
                container: containerLevel,
                video: videoLevel,
                audio: audioLevel,
                subtitle: subtitleLevel,
                hdr: .supported
            ),
            preferredBackend: preferredBackend,
            preferredPath: preferredPath,
            reasons: reasons,
            nativeCandidate: nativeCandidate
        )
    }

    // MARK: - Dimensions

    private func analyzeContainer(_ raw: String?) -> CompatibilityLevel {
        guard let c = IOSCapabilities.normalizeContainer(raw) else { return .unsupported }
        // AVPlayer-friendly
        if ["mp4", "m4v", "mov", "mpegts", "hls", "m3u8", "isom"].contains(c) {
            return .supported
        }
        // Native engine targets (Phase 2+ demux)
        if ["mkv", "webm", "avi", "flv", "vob", "m2ts", "mts"].contains(c) {
            return nativeEngineEnabled ? .softwareSupported : .unsupported
        }
        return .unsupported
    }

    private func analyzeVideo(_ raw: String?) -> CompatibilityLevel {
        guard let c = IOSCapabilities.normalizeVideoCodec(raw) else { return .unsupported }
        let vt = VideoToolboxCapabilities.shared
        switch c {
        case "h264":
            return vt.supportsH264Hardware ? .hardwareSupported : .unsupported
        case "mpeg4", "mpeg2video":
            return .hardwareSupported
        case "hevc":
            return vt.supportsHEVCHardware ? .hardwareSupported : .unsupported
        case "av1":
            return capabilities.supportsAV1 ? .hardwareSupported : .softwareSupported
        case "vp9":
            return nativeEngineEnabled ? .softwareSupported : .unsupported
        default:
            return .unsupported
        }
    }

    private func analyzeAudio(_ raw: String?) -> CompatibilityLevel {
        guard let c = IOSCapabilities.normalizeAudioCodec(raw) else { return .unsupported }
        if capabilities.supportsAudioCodec(c) {
            return .supported
        }
        // Opus / DTS / TrueHD → software path in native engine (Phase 5/9)
        if ["opus", "vorbis", "dca", "truehd", "wma"].contains(c) {
            return nativeEngineEnabled ? .softwareSupported : .unsupported
        }
        return .unsupported
    }

    private func analyzeSubtitle(
        _ streams: [PlexStream],
        selectedId: Int?,
        burnIn: Bool
    ) -> CompatibilityLevel {
        if burnIn { return .supported }
        guard let id = selectedId,
              let stream = streams.first(where: { $0.id == id })
        else { return .supported }
        if capabilities.requiresBurnIn(stream) {
            return nativeEngineEnabled ? .softwareSupported : .unsupported
        }
        if capabilities.supportsSubtitleNatively(stream) {
            return .supported
        }
        return .softwareSupported
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
