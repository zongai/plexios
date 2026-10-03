import Foundation

/// Cross-platform playback contract surface for iOS backends.
/// See `docs/cross-platform-playback-contract.md`.
///
/// `PlaybackEngine` remains the orchestrator (Decision, Session, Timeline, NowPlaying).
/// Concrete backends implement this protocol; UI talks only to the Engine.
@MainActor
protocol MediaPlayerProtocol: AnyObject {
    func play()
    func pause()
    func stop() async
    func seek(toMs positionMs: Int64) async
    func setRate(_ rate: Float)
    func setVolume(_ volume: Float)

    var positionMs: Int64 { get }
    var durationMs: Int64 { get }
    var rate: Float { get }
    var volume: Float { get }
    var isPlaying: Bool { get }
}
