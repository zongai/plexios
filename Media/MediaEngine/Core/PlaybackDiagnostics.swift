import Foundation

/// Human-readable playback diagnostics for UI / logs.
struct PlaybackDiagnostics: Sendable, Equatable {
    var container: String?
    var videoSummary: String?
    var audioSummary: String?
    var subtitleSummary: String?
    var videoDecoder: String?
    var audioDecoder: String?
    var renderer: String?
    var path: PlaybackPath?
    var backend: PlaybackBackend?
    var decisionReason: String?
    var failureStage: String?
    var failureReason: String?

    var displayLines: [String] {
        [
            container.map { "Container: \($0)" },
            videoSummary.map { "Video: \($0)" },
            audioSummary.map { "Audio: \($0)" },
            subtitleSummary.map { "Subtitle: \($0)" },
            videoDecoder.map { "Video Decoder: \($0)" },
            audioDecoder.map { "Audio Decoder: \($0)" },
            renderer.map { "Renderer: \($0)" },
            path.map { "Path: \($0.rawValue)" },
            backend.map { "Backend: \($0.rawValue)" },
            decisionReason.map { "Decision: \($0)" },
            failureStage.map { "Failed Stage: \($0)" },
            failureReason.map { "Failed Reason: \($0)" }
        ].compactMap { $0 }
    }

    static func from(
        info: MediaInfo?,
        decision: PlaybackDecision,
        report: CompatibilityReport,
        failure: PlaybackFailure? = nil
    ) -> PlaybackDiagnostics {
        let video = info?.videoTracks.first
        let audio = info?.audioTracks.first
        let sub = info?.subtitleTracks.first
        return PlaybackDiagnostics(
            container: info?.container.format,
            videoSummary: video.map {
                "\($0.codec ?? "?") \($0.width ?? 0)x\($0.height ?? 0)"
            },
            audioSummary: audio.map {
                "\($0.codec ?? "?") ch=\($0.channels ?? 0)"
            },
            subtitleSummary: sub.map {
                "\($0.format ?? "?") \($0.language ?? "")"
            },
            videoDecoder: report.preferredBackend == .avPlayer
                ? "AVPlayer / system"
                : (report.tracks.video == .hardwareSupported ? "VideoToolbox HW" : "Software (planned)"),
            audioDecoder: report.preferredBackend == .avPlayer ? "AVPlayer / system" : "Native (planned)",
            renderer: report.preferredBackend == .avPlayer ? "AVPlayerLayer" : "Metal (planned)",
            path: report.preferredPath,
            backend: report.preferredBackend,
            decisionReason: decision.reason,
            failureStage: failure?.stage.rawValue,
            failureReason: failure?.reason
        )
    }
}
