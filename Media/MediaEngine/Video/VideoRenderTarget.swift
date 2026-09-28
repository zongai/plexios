import CoreVideo
import Foundation

/// Phase 3 sink: holds last decoded frame for Phase 4 Metal to consume.
/// Does **not** convert to UIImage.
/// Thread-safe: written from decode/pipeline threads, read from UI.
final class VideoFrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private var _latestFrame: VideoFrame?
    private var _frameCount: Int = 0

    var latestFrame: VideoFrame? {
        lock.lock(); defer { lock.unlock() }
        return _latestFrame
    }

    var frameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _frameCount
    }

    func present(_ frame: VideoFrame) {
        lock.lock()
        _latestFrame = frame
        _frameCount += 1
        lock.unlock()
    }

    func clear() {
        lock.lock()
        _latestFrame = nil
        _frameCount = 0
        lock.unlock()
    }
}
