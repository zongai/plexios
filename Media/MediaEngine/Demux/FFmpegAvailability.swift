import Foundation

/// Compile-time / runtime gate for Native demux & soft decode.
enum FFmpegAvailability {
    /// Set when building with `-DNATIVE_FFMPEG` and linked libav* XCFrameworks.
    static var isLinked: Bool {
        #if NATIVE_FFMPEG
        return true
        #else
        return false
        #endif
    }

    static var statusMessage: String {
        if isLinked {
            return "FFmpeg linked (NATIVE_FFMPEG)"
        }
        return "FFmpeg not linked — Native Direct Play disabled; use AVPlayer / Transcode. See docs/ffmpeg-integration.md"
    }
}
