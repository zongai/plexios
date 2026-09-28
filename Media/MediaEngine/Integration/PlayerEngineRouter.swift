import Foundation
import Observation

@Observable
@MainActor
final class PlayerEngineRouter {
    private(set) var lastReport: CompatibilityReport?
    private(set) var lastPath: PlaybackPath = .avPlayerDirect
    private(set) var lastBackend: PlaybackBackend = .avPlayer
    private(set) var diagnosticsLine: String = ""
    private(set) var activeBackend: PlaybackBackend = .avPlayer

    private var analyzer: PlaybackCompatibilityAnalyzer
    private let fallback: PlaybackFallbackPolicy
    private let logger: LogRouter
    private let nativeBackend: NativeMediaBackend

    var nativeEngineEnabled: Bool {
        didSet {
            analyzer = PlaybackCompatibilityAnalyzer(
                capabilities: .current,
                nativeEngineEnabled: nativeEngineEnabled
            )
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

    func resolve(
        metadata: PlexMetadata,
        decision: PlaybackDecision,
        network: NetworkClass
    ) -> CompatibilityReport {
        let enabled = PlaybackSettingsStore.shared.preferences.allowNativeMediaEngine
        if enabled != nativeEngineEnabled {
            nativeEngineEnabled = enabled
        }
        let report = analyzer.analyze(
            metadata: metadata,
            decision: decision,
            network: network
        )
        lastReport = report
        lastPath = report.preferredPath
        lastBackend = report.preferredBackend
        diagnosticsLine = formatDiagnostics(report: report, decision: decision)
        if enabled && !FFmpegAvailability.isLinked {
            logger.playback.info("Native toggle on but \(FFmpegAvailability.statusMessage)")
        }
        logger.playback.info("Router: \(self.diagnosticsLine)")
        return report
    }

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

    func nativeBackendInstance() -> NativeMediaBackend { nativeBackend }

    func markActive(_ backend: PlaybackBackend) {
        activeBackend = backend
        lastBackend = backend
    }

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
