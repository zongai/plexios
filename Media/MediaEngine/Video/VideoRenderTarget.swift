import CoreVideo
import Foundation

/// Phase 3 sink: holds last decoded frame for Phase 4 Metal to consume.
/// Does **not** convert to UIImage.
@MainActor
final class VideoFrameSink {
    private(set) var latestFrame: VideoFrame?
    private(set) var frameCount: Int = 0

    func present(_ frame: VideoFrame) {
        latestFrame = frame
        frameCount += 1
    }

    func clear() {
        latestFrame = nil
        frameCount = 0
    }
}
