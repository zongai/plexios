import XCTest
@testable import PlexiOS

final class MediaClockTests: XCTestCase {
    func testResetAndSeek() {
        let clock = MediaClock()
        clock.reset(startMs: 1_000)
        clock.seek(toMs: 5_000)
        XCTAssertEqual(clock.currentMediaTimeMs(), 5_000)
    }

    func testPauseFreezesExternalClock() async throws {
        let clock = MediaClock()
        clock.reset(startMs: 0)
        try await Task.sleep(for: .milliseconds(50))
        clock.pause()
        let a = clock.currentMediaTimeMs()
        try await Task.sleep(for: .milliseconds(80))
        let b = clock.currentMediaTimeMs()
        XCTAssertEqual(a, b)
        clock.resume()
    }

    func testAudioMasterSkew() {
        let clock = MediaClock()
        clock.reset(startMs: 0)
        clock.setAudioPts(1_000)
        XCTAssertEqual(clock.currentMediaTimeMs(), 1_000)
        let skew = clock.videoSkewMs(videoPts: 1_030)
        XCTAssertEqual(skew, 30)
    }

    func testBufferLimits() {
        let buf = BufferManager(limits: .init(maxVideoPackets: 2))
        let pkt = MediaPacket(
            kind: .video, streamIndex: 0, data: Data([0]),
            ptsMs: 0, dtsMs: 0, durationMs: 40, isKeyFrame: true
        )
        XCTAssertTrue(buf.pushPacket(pkt))
        XCTAssertTrue(buf.pushPacket(pkt))
        XCTAssertFalse(buf.pushPacket(pkt))
        XCTAssertNotNil(buf.popVideoPacket())
    }

    func testSeekController() {
        let s = SeekController()
        XCTAssertFalse(s.isSeeking)
        s.begin(targetMs: 1234)
        XCTAssertTrue(s.isSeeking)
        XCTAssertEqual(s.targetMs, 1234)
        s.complete()
        XCTAssertFalse(s.isSeeking)
    }
}
