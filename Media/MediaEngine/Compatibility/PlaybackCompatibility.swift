import Foundation

/// Fine-grained support level for a single dimension (container / video / audio / …).
enum CompatibilityLevel: String, Sendable, Equatable {
    case supported
    case hardwareSupported
    case softwareSupported
    case unsupported
}

struct TrackCompatibility: Sendable, Equatable {
    var container: CompatibilityLevel
    var video: CompatibilityLevel
    var audio: CompatibilityLevel
    var subtitle: CompatibilityLevel
    var hdr: CompatibilityLevel
}

struct CompatibilityReport: Sendable, Equatable {
    var tracks: TrackCompatibility
    /// Preferred backend if prediction is trusted.
    var preferredBackend: PlaybackBackend
    var preferredPath: PlaybackPath
    var reasons: [String]
    /// When true, router may try native before transcode.
    var nativeCandidate: Bool
}

/// Device / OS capability snapshot used by the analyzer (Phase 1: mirrors IOSCapabilities).
struct VideoDecodeCapability: Sendable, Equatable {
    var codec: String
    var profile: String?
    var bitDepth: Int
    var maxWidth: Int
    var maxHeight: Int
    var maxFrameRate: Double
    var hardware: Bool
}
