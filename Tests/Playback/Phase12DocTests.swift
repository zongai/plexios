
import XCTest
@testable import PlexiOS

/// Ensures Phase 11 capability matrix stays aligned with Phase 12 docs.
final class Phase12DocTests: XCTestCase {
    func testKnownLimitationMatrixMatchesCode() {
        let c = NativeSystemCapabilities.metalPipeline
        XCTAssertFalse(c.pictureInPicture)
        XCTAssertFalse(c.airPlayVideo)
        XCTAssertTrue(c.nowPlaying && c.backgroundAudio)
    }
}
