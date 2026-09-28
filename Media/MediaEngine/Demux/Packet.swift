import Foundation

/// Encoded media packet from demuxer (not decoded frames).
struct MediaPacket: Sendable, Equatable {
    enum Kind: String, Sendable {
        case video
        case audio
        case subtitle
        case unknown
    }

    var kind: Kind
    var streamIndex: Int
    var data: Data
    /// Presentation timestamp in milliseconds (best-effort).
    var ptsMs: Int64?
    /// Decode timestamp in milliseconds.
    var dtsMs: Int64?
    var durationMs: Int64?
    var isKeyFrame: Bool
}

struct DemuxStreamInfo: Sendable, Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var kind: MediaPacket.Kind
    var codecName: String?
    var codecTag: String?
    var width: Int?
    var height: Int?
    var sampleRate: Int?
    var channels: Int?
    var language: String?
    var bitrate: Int?
    var extradata: Data?
}
