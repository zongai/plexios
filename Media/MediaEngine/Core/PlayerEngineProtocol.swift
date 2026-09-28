import Foundation

/// Intent surface shared by AVPlayer and Native backends.
/// UI and Plex session code talk to `PlaybackEngine` / router — not backends directly.
@MainActor
protocol PlayerEngineBackend: AnyObject {
    var backendKind: PlaybackBackend { get }
    var state: MediaEngineSessionState { get }
    var positionMs: Int64 { get }
    var durationMs: Int64 { get }
    var rate: Float { get }

    func prepare(request: PlaybackRequest) async throws
    func play()
    func pause()
    func stop() async
    func seek(toMs ms: Int64) async
    func setRate(_ rate: Float)

    func selectAudio(streamId: Int) async
    func selectSubtitle(streamId: Int?) async
}

struct PlaybackRequest: Sendable {
    let metadata: PlexMetadata
    let context: ServerContext
    let network: NetworkClass
    let path: PlaybackPath
    let decision: PlaybackDecision
    let mediaURL: URL
    let startPositionMs: Int64
    let preferences: PlaybackPreferences
}

struct PlaybackFailure: Error, Sendable {
    enum Stage: String, Sendable {
        case probe
        case demux
        case videoDecoder
        case audioDecoder
        case subtitle
        case renderer
        case buffer
        case network
        case unknown
    }

    let stage: Stage
    let reason: String
    let underlying: String?

    var localizedDescription: String {
        "[\(stage.rawValue)] \(reason)"
    }
}
