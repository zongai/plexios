import Foundation

enum DemuxError: Error, LocalizedError, Sendable {
    case notOpen
    case openFailed(String)
    case readFailed(String)
    case seekFailed
    case unsupported
    case endOfStream
    case ffmpegNotLinked

    var errorDescription: String? {
        switch self {
        case .notOpen: return "Demuxer not open"
        case .openFailed(let s): return "Open failed: \(s)"
        case .readFailed(let s): return "Read failed: \(s)"
        case .seekFailed: return "Seek failed"
        case .unsupported: return "Container/codec unsupported by demuxer"
        case .endOfStream: return "End of stream"
        case .ffmpegNotLinked: return "FFmpeg not linked (enable NATIVE_FFMPEG + XCFramework)"
        }
    }
}

/// Asynchronous demux surface used by Native Media Engine.
protocol Demuxer: AnyObject, Sendable {
    var isOpen: Bool { get async }
    var streams: [DemuxStreamInfo] { get async }
    var durationMs: Int64? { get async }
    var formatName: String? { get async }

    func open(url: URL, headers: [String: String]) async throws
    func close() async
    /// Read next packet; returns nil at EOS.
    func nextPacket() async throws -> MediaPacket?
    /// Seek to approximate timestamp (milliseconds).
    func seek(toMs ms: Int64) async throws
}

/// Factory selects implementation: FFmpeg when linked, otherwise limited built-in probe demux.
enum DemuxerFactory {
    static func make() -> any Demuxer {
        if FFmpegAvailability.isLinked {
            return FFmpegDemuxer()
        }
        return BuiltinContainerDemuxer()
    }
}
