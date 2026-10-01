import Foundation

/// Which concrete player handles the session.
enum PlaybackBackend: String, Sendable, Equatable {
    case avPlayer
    case nativeMediaEngine
    /// MobileVLCKit (libVLC 3.x) Direct Play — legacy path during migration.
    case vlc
    /// SwiftVLC (libVLC 4.0) Direct Play — feature/swiftvlc-migration.
    case swiftVLC
}

/// High-level path chosen before (and possibly revised after) runtime failures.
enum PlaybackPath: String, Sendable, Equatable {
    case avPlayerDirect
    case avPlayerHLS          // Direct Stream / Transcode universal HLS
    case nativeDirectPlay
    case nativeDirectStream
    case vlcDirectPlay
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
