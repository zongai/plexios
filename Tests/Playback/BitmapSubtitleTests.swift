import XCTest
@testable import PlexiOS

final class BitmapSubtitleTests: XCTestCase {
    func testFormatDetection() {
        XCTAssertEqual(BitmapSubtitleFormat.from(codecOrFormat: "hdmv_pgs_subtitle"), .pgs)
        XCTAssertEqual(BitmapSubtitleFormat.from(codecOrFormat: "PGS"), .pgs)
        XCTAssertEqual(BitmapSubtitleFormat.from(codecOrFormat: "dvd_subtitle"), .vobsub)
        XCTAssertEqual(BitmapSubtitleFormat.from(codecOrFormat: "vobsub"), .vobsub)
    }

    func testPGSFactory() throws {
        let dec = try BitmapSubtitleDecoderFactory.make(format: .pgs)
        XCTAssertEqual(dec.format, .pgs)
        // Empty packet → no cue
        let pkt = MediaPacket(
            kind: .subtitle, streamIndex: 0, data: Data(),
            ptsMs: 0, dtsMs: nil, durationMs: nil, isKeyFrame: false
        )
        let cues = try dec.push(packet: pkt)
        XCTAssertTrue(cues.isEmpty)
    }

    func testVobSubIncompleteReturnsEmpty() throws {
        let dec = try BitmapSubtitleDecoderFactory.make(format: .vobsub)
        let pkt = MediaPacket(
            kind: .subtitle, streamIndex: 0, data: Data([0x00, 0x10, 0x00]),
            ptsMs: 1000, dtsMs: nil, durationMs: nil, isKeyFrame: false
        )
        let cues = try dec.push(packet: pkt)
        XCTAssertTrue(cues.isEmpty)
    }

    func testPDSPaletteDoesNotCrash() throws {
        let dec = PGSSubtitleDecoder()
        // Minimal PDS-like segment: type 0x14, size, payload
        var data = Data([0x14, 0x00, 0x07, 0x00, 0x00])
        data.append(contentsOf: [0x01, 16, 128, 128, 255]) // id, Y, Cr, Cb, A
        let pkt = MediaPacket(
            kind: .subtitle, streamIndex: 0, data: data,
            ptsMs: 0, dtsMs: nil, durationMs: nil, isKeyFrame: false
        )
        _ = try dec.push(packet: pkt)
    }
}
