import Foundation

#if NATIVE_FFMPEG
import FFmpegSupport // XCFramework module name — see docs/ffmpeg-integration.md
#endif

/// FFmpeg-backed demuxer. Compiled only when `NATIVE_FFMPEG` is set and libs linked.
/// Without the flag this type still exists as documentation + runtime error path.
actor FFmpegDemuxer: Demuxer {
    private(set) var isOpen = false
    private(set) var streams: [DemuxStreamInfo] = []
    private(set) var durationMs: Int64?
    private(set) var formatName: String?

    #if NATIVE_FFMPEG
    // Opaque FFmpeg context pointers managed in C shim
    private var formatContext: OpaquePointer?
    #endif

    func open(url: URL, headers: [String: String]) async throws {
        #if NATIVE_FFMPEG
        try await openFFmpeg(url: url, headers: headers)
        #else
        throw DemuxError.ffmpegNotLinked
        #endif
    }

    func close() async {
        #if NATIVE_FFMPEG
        await closeFFmpeg()
        #endif
        isOpen = false
        streams = []
        durationMs = nil
        formatName = nil
    }

    func nextPacket() async throws -> MediaPacket? {
        #if NATIVE_FFMPEG
        return try await readPacketFFmpeg()
        #else
        throw DemuxError.ffmpegNotLinked
        #endif
    }

    func seek(toMs ms: Int64) async throws {
        #if NATIVE_FFMPEG
        try await seekFFmpeg(ms: ms)
        #else
        throw DemuxError.ffmpegNotLinked
        #endif
    }

    #if NATIVE_FFMPEG
    private func openFFmpeg(url: URL, headers: [String: String]) async throws {
        // Implemented in FFmpegSupport C/ObjC++ shim:
        // avformat_open_input with AVIO callbacks for HTTP Range via HTTPRangeDataSource
        throw DemuxError.openFailed("FFmpegSupport open not yet bound — complete C shim")
    }

    private func closeFFmpeg() async {}
    private func readPacketFFmpeg() async throws -> MediaPacket? { nil }
    private func seekFFmpeg(ms: Int64) async throws {}
    #endif
}
