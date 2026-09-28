import Foundation

/// Which concrete player handles the session.
enum PlaybackBackend: String, Sendable, Equatable {
    case avPlayer
    case nativeMediaEngine
}

/// High-level path chosen before (and possibly revised after) runtime failures.
enum PlaybackPath: String, Sendable, Equatable {
    case avPlayerDirect
    case avPlayerHLS          // Direct Stream / Transcode universal HLS
    case nativeDirectPlay
    case nativeDirectStream
    case plexTranscode        // always via AVPlayer + HLS
}

enum MediaEngineSessionState: String, Sendable {
    case idle
    case loading
    case buffering
    case playing
    case paused
    case seeking
    case stopped
    case failed
    case fallback
}
