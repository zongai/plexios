import XCTest
@testable import PlexiOS

final class VideoToolboxDecoderTests: XCTestCase {
    func testCapabilitiesProbeDoesNotCrash() {
        let caps = VideoToolboxCapabilities.shared
        _ = caps.supportsH264Hardware
        _ = caps.supportsHEVCHardware
        let list = caps.decodeCapabilities()
        // Simulator may or may not report HW; just ensure API works
        XCTAssertFalse(caps.summaryLine.isEmpty)
        XCTAssertNotNil(list)
    }

    func testFactoryH264() throws {
        let caps = VideoToolboxCapabilities.shared
        if caps.supportsH264Hardware {
            let decoder = try VideoDecoderFactory.make(codec: .h264)
            XCTAssertEqual(decoder.codec, .h264)
            XCTAssertFalse(decoder.isReady)
            // Setup without extradata should still create a session on many devices
            try decoder.setup(config: VideoDecoderConfig(
                codec: .h264,
                width: 1920,
                height: 1080,
                extradata: nil,
                bitDepth: 8
            ))
            XCTAssertTrue(decoder.isReady)
            decoder.invalidate()
            XCTAssertFalse(decoder.isReady)
        } else {
            XCTAssertThrowsError(try VideoDecoderFactory.make(codec: .h264))
        }
    }

    func testCodecIDNormalization() {
        XCTAssertEqual(VideoCodecID.from(codecName: "h265"), .hevc)
        XCTAssertEqual(VideoCodecID.from(codecName: "avc1"), .h264)
        XCTAssertEqual(VideoCodecID.from(codecName: "vp9"), .unknown)
    }

    func testSoftwareDecoderStubThrows() {
        let soft = SoftwareVideoDecoder(codec: .h264)
        XCTAssertThrowsError(try soft.setup(config: VideoDecoderConfig(
            codec: .h264, width: 64, height: 64, extradata: nil, bitDepth: 8
        )))
    }
}
