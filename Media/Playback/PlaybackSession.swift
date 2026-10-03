import Foundation

/// Contract-aligned states (see docs/cross-platform-playback-contract.md §4):
/// idle | loading | ready | buffering | playing | paused | ended | stopped | error
///
/// Mapping notes:
/// - `loading`  == contract loading (prepare / open)
/// - `buffering` is NOT paused — UI play/pause follows `PlaybackEngine.isPlaying`
/// - no separate `ready` / `ended` here; ended is handled via player callbacks + stop
/// Contract-aligned states (docs/cross-platform-playback-contract.md §4):
/// idle | loading | ready | buffering | playing | paused | ended | stopped | error
///
/// Mapping notes:
/// - `loading` == contract loading (prepare / open)
/// - `buffering` is NOT paused — UI play/pause follows `PlaybackEngine.isPlaying`
/// - no separate `ready` here; prepared-but-not-playing is represented as paused/idle at session level
/// - natural end is handled via player callbacks then stop/ended transition
enum PlaybackSessionState: String, Sendable {
    case idle
    case loading
    case playing
    case paused
    case buffering
    case stopped
    case error
}

/// Tracks local playback progress and throttles timeline reports to PMS.
actor PlaybackSession {
    let sessionId: String
    let ratingKey: String
    let metadataKey: String
    let durationMs: Int64
    let decision: PlaybackDecision

    private(set) var state: PlaybackSessionState = .idle
    private(set) var positionMs: Int64 = 0
    private var lastReportedPositionMs: Int64 = -1
    private var lastReportTime: ContinuousClock.Instant?
    private let reportInterval: Duration

    init(
        sessionId: String = UUID().uuidString.lowercased(),
        ratingKey: String,
        metadataKey: String,
        durationMs: Int64,
        decision: PlaybackDecision,
        startPositionMs: Int64 = 0,
        reportIntervalSeconds: Double = 10
    ) {
        self.sessionId = sessionId
        self.ratingKey = ratingKey
        self.metadataKey = metadataKey
        self.durationMs = durationMs
        self.decision = decision
        self.positionMs = startPositionMs
        self.reportInterval = .seconds(reportIntervalSeconds)
    }

    func updateState(_ newState: PlaybackSessionState) {
        state = newState
    }

    func updatePosition(_ ms: Int64) {
        positionMs = max(0, ms)
    }

    /// Returns true if a timeline report should be sent now.
    func shouldReport(force: Bool = false) -> Bool {
        if force { return true }
        if state == .playing || state == .paused || state == .buffering {
            let now = ContinuousClock.now
            if let last = lastReportTime {
                if now - last >= reportInterval {
                    return true
                }
                // Also report significant seeks
                if abs(positionMs - lastReportedPositionMs) > 5000 {
                    return true
                }
            } else {
                return true
            }
        }
        return false
    }

    func markReported() {
        lastReportedPositionMs = positionMs
        lastReportTime = ContinuousClock.now
    }

    var plexStateString: String {
        switch state {
        case .playing: return "playing"
        case .paused: return "paused"
        case .buffering: return "buffering"
        case .stopped, .idle, .error, .loading: return "stopped"
        }
    }
}
