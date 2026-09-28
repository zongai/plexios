import XCTest
@testable import PlexiOS

final class SoftwareVideoDecoderTests: XCTestCase {
    func testFallbackChainH264PrefersHardwareWhenAvailable() {
        let outcome = VideoDecodeFallbackChain.open(codec: .h264)
        if VideoToolboxCapabilities.shared.supportsH264Hardware {
            XCTAssertEqual(outcome.stage, .videoToolbox)
        } else {
            XCTAssertEqual(outcome.stage, .software)
        }
    }

    func testVP9GoesSoftware() {
        let outcome = VideoDecodeFallbackChain.open(codec: .vp9)
        XCTAssertEqual(outcome.stage, .software)
        XCTAssertNotNil(outcome.decoder)
    }

    func testSoftwareSetupDependsOnFFmpeg() {
        let soft = SoftwareVideoDecoder(codec: .vp9)
        if FFmpegAvailability.isLinked {
            // May still fail if binary lacks vp9 decoder; must not crash.
            _ = try? soft.setup(config: VideoDecoderConfig(
                codec: .vp9, width: 1920, height: 1080, extradata: nil, bitDepth: 8
            ))
            soft.invalidate()
        } else {
            XCTAssertThrowsError(try soft.setup(config: VideoDecoderConfig(
                codec: .vp9, width: 1920, height: 1080, extradata: nil, bitDepth: 8
            )))
        }
    }

    func testCodecIDVP9() {
        XCTAssertEqual(VideoCodecID.from(codecName: "vp9"), .vp9)
        XCTAssertEqual(VideoCodecID.from(codecName: "av1"), .av1)
    }
}
