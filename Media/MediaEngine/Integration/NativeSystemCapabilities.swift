import Foundation

/// What the Native Media Engine can offer relative to AVPlayer system features.
struct NativeSystemCapabilities: Sendable, Equatable {
    var nowPlaying: Bool
    var lockScreenControls: Bool
    var remoteCommands: Bool
    var backgroundAudio: Bool
    var pictureInPicture: Bool
    var airPlayVideo: Bool
    var airPlayAudio: Bool

    /// Default realistic matrix for Phase 11 (Metal + AVAudioEngine path).
    static let metalPipeline = NativeSystemCapabilities(
        nowPlaying: true,
        lockScreenControls: true,
        remoteCommands: true,
        backgroundAudio: true,
        // True PiP needs AVPlayer / AVSampleBufferDisplayLayer sample path.
        // Metal MTKView cannot enter system PiP without a sample-buffer bridge.
        pictureInPicture: false,
        // External video route typically requires AVPlayer externalPlayback.
        airPlayVideo: false,
        // Audio can follow system route via AVAudioSession.
        airPlayAudio: true
    )

    var unavailableNotes: [String] {
        var notes: [String] = []
        if !pictureInPicture {
            notes.append("PiP: not available on pure Metal path (use AVPlayer backend or future SampleBuffer bridge)")
        }
        if !airPlayVideo {
            notes.append("AirPlay Video: not available on pure Metal path (audio routing still works)")
        }
        return notes
    }
}

/// Publishes capability snapshot for Settings / Player UI.
@Observable
@MainActor
final class NativeSystemCapabilityStore {
    var current: NativeSystemCapabilities = .metalPipeline

    var summaryLines: [String] {
        let c = current
        return [
            "Now Playing: \(c.nowPlaying ? "Yes" : "No")",
            "Lock Screen: \(c.lockScreenControls ? "Yes" : "No")",
            "Remote Commands: \(c.remoteCommands ? "Yes" : "No")",
            "Background Audio: \(c.backgroundAudio ? "Yes" : "No")",
            "Picture in Picture: \(c.pictureInPicture ? "Yes" : "No")",
            "AirPlay Video: \(c.airPlayVideo ? "Yes" : "No")",
            "AirPlay Audio: \(c.airPlayAudio ? "Yes" : "No")",
        ] + c.unavailableNotes
    }
}
