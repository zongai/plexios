import Foundation

/// Coordinates seek: flush buffers, demux seek, decoder flush, clock reset.
final class SeekController: @unchecked Sendable {
    enum State: String, Sendable {
        case idle
        case seeking
    }

    private let lock = NSLock()
    private(set) var state: State = .idle
    private(set) var targetMs: Int64 = 0

    func begin(targetMs: Int64) {
        lock.lock()
        state = .seeking
        self.targetMs = max(0, targetMs)
        lock.unlock()
    }

    func complete() {
        lock.lock()
        state = .idle
        lock.unlock()
    }

    var isSeeking: Bool {
        lock.lock(); defer { lock.unlock() }
        return state == .seeking
    }
}
