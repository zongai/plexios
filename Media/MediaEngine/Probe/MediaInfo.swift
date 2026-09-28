import Foundation

/// Probe results (Phase 2 fills from FFmpeg). Phase 1 types only.
struct MediaInfo: Sendable, Equatable {
    var container: ContainerInfo
    var durationMs: Int64?
    var bitrate: Int?
    var seekable: Bool
    var videoTracks: [VideoTrackInfo]
    var audioTracks: [AudioTrackInfo]
    var subtitleTracks: [SubtitleTrackInfo]
}

struct ContainerInfo: Sendable, Equatable {
    var format: String?
    var formatLongName: String?
}

struct VideoTrackInfo: Sendable, Equatable, Identifiable {
    var id: Int
    var codec: String?
    var profile: String?
    var level: String?
    var width: Int?
    var height: Int?
    var frameRate: Double?
    var bitDepth: Int?
    var pixelFormat: String?
    var isHDR: Bool
    var colorPrimaries: String?
    var transfer: String?
    var matrix: String?
}

struct AudioTrackInfo: Sendable, Equatable, Identifiable {
    var id: Int
    var codec: String?
    var sampleRate: Int?
    var channels: Int?
    var channelLayout: String?
    var bitrate: Int?
    var bitDepth: Int?
    var language: String?
}

struct SubtitleTrackInfo: Sendable, Equatable, Identifiable {
    var id: Int
    var format: String?
    var language: String?
    var isForced: Bool
    var isHearingImpaired: Bool
    var isText: Bool
}
