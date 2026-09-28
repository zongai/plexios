import Foundation

/// Runtime failure → next path. Finite steps only.
struct PlaybackFallbackPolicy: Sendable {
    struct Step: Sendable, Equatable {
        let path: PlaybackPath
        let backend: PlaybackBackend
        let note: String
    }

    /// Ordered attempts after the initial choice fails.
    func nextSteps(
        after failedPath: PlaybackPath,
        failure: PlaybackFailure?,
        report: CompatibilityReport
    ) -> [Step] {
        var steps: [Step] = []

        switch failedPath {
        case .nativeDirectPlay, .nativeDirectStream:
            // Native hard → native soft is owned inside native engine; router falls to AV/HLS
            steps.append(Step(
                path: .avPlayerHLS,
                backend: .avPlayer,
                note: "Native failed (\(failure?.stage.rawValue ?? "?")): try HLS Direct Stream"
            ))
            steps.append(Step(
                path: .plexTranscode,
                backend: .avPlayer,
                note: "Force Plex transcode"
            ))

        case .avPlayerDirect:
            steps.append(Step(
                path: .avPlayerHLS,
                backend: .avPlayer,
                note: "AVPlayer Direct Play failed → universal HLS"
            ))
            steps.append(Step(
                path: .plexTranscode,
                backend: .avPlayer,
                note: "Force transcode"
            ))

        case .avPlayerHLS:
            steps.append(Step(
                path: .plexTranscode,
                backend: .avPlayer,
                note: "HLS path failed → full transcode flags"
            ))

        case .plexTranscode:
            // Terminal for Phase 1
            break
        }

        // Cap retries
        return Array(steps.prefix(3))
    }
}
