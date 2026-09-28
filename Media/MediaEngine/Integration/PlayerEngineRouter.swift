import Foundation
import Observation

/// Chooses backend / path using Analyzer + FallbackPolicy.
/// Phase 1: always executes via existing `PlaybackEngine` AVPlayer path;
/// reports diagnostics and records preferred native candidacy for later phases.
@Observable
@MainActor
final class PlayerEngineRouter {
    private(set) var lastReport: CompatibilityReport?
    private(set) var lastPath: PlaybackPath = .avPlayerDirect
    private(set) var lastBackend: PlaybackBackend = .avPlayer
    private(set) var diagnosticsLine: String = ""

    private let analyzer: PlaybackCompatibilityAnalyzer
    private let fallback: PlaybackFallbackPolicy
    private let logger: LogRouter
    private let nativeBackend: NativeMediaBackend

    /// When true (future Settings), analyzer may mark nativeCandidate.
    var nativeEngineEnabled: Bool {
        didSet {
            // Recreate analyzer with flag — kept simple for Phase 1
        }
    }

    init(logger: LogRouter, nativeEngineEnabled: Bool = false) {
        self.logger = logger
        self.nativeEngineEnabled = nativeEngineEnabled
        self.analyzer = PlaybackCompatibilityAnalyzer(
            capabilities: .current,
            nativeEngineEnabled: nativeEngineEnabled
        )
        self.fallback = PlaybackFallbackPolicy()
        self.nativeBackend = NativeMediaBackend(logger: logger)
    }

    /// Predict path; does not start playback. Used by PlaybackEngine before AVPlayer play.
    func resolve(
        metadata: PlexMetadata,
        decision: PlaybackDecision,
        network: NetworkClass
    ) -> CompatibilityReport {
        let report = analyzer.analyze(
            metadata: metadata,
            decision: decision,
            network: network
        )
        lastReport = report
        lastPath = report.preferredPath
        lastBackend = report.preferredBackend
        diagnosticsLine = formatDiagnostics(report: report, decision: decision)
        logger.playback.info("Router: \(diagnosticsLine)")
        return report
    }

    /// Ordered fallbacks after a runtime failure on `path`.
    func fallbackSteps(after path: PlaybackPath, failure: PlaybackFailure?) -> [PlaybackFallbackPolicy.Step] {
        let report = lastReport ?? CompatibilityReport(
            tracks: TrackCompatibility(
                container: .unsupported,
                video: .unsupported,
                audio: .unsupported,
                subtitle: .unsupported,
                hdr: .supported
            ),
            preferredBackend: .avPlayer,
            preferredPath: .plexTranscode,
            reasons: ["no prior report"],
            nativeCandidate: false
        )
        return fallback.nextSteps(after: path, failure: failure, report: report)
    }

    /// Phase 1: native prepare always fails → caller should not use for production play.
    func nativeBackendInstance() -> NativeMediaBackend { nativeBackend }

    private func formatDiagnostics(report: CompatibilityReport, decision: PlaybackDecision) -> String {
        let t = report.tracks
        return [
            "path=\(report.preferredPath.rawValue)",
            "backend=\(report.preferredBackend.rawValue)",
            "mode=\(decision.mode.rawValue)",
            "container=\(t.container.rawValue)",
            "video=\(t.video.rawValue)",
            "audio=\(t.audio.rawValue)",
            "sub=\(t.subtitle.rawValue)",
            "nativeCandidate=\(report.nativeCandidate)",
            report.reasons.prefix(2).joined(separator: "; ")
        ].filter { !$0.isEmpty }.joined(separator: " | ")
    }
}
