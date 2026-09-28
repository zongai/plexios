import XCTest
@testable import PlexiOS

final class NativeSystemCapabilitiesTests: XCTestCase {
    func testMetalPipelineMatrix() {
        let c = NativeSystemCapabilities.metalPipeline
        XCTAssertTrue(c.nowPlaying)
        XCTAssertTrue(c.lockScreenControls)
        XCTAssertTrue(c.remoteCommands)
        XCTAssertTrue(c.backgroundAudio)
        XCTAssertTrue(c.airPlayAudio)
        XCTAssertFalse(c.pictureInPicture)
        XCTAssertFalse(c.airPlayVideo)
        XCTAssertFalse(c.unavailableNotes.isEmpty)
    }
}
