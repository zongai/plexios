import Foundation

/// Snapshot published to UI / diagnostics for Native pipeline.
struct NativePlaybackSnapshot: Sendable, Equatable {
    var state: PlaybackPipeline.State
    var positionMs: Int64
    var bufferedMs: Int64
    var videoPackets: Int
    var audioPackets: Int
    var videoFrames: Int
    var rate: Double
    var error: String?
}
