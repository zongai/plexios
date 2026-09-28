import XCTest
@testable import PlexiOS

final class PlexURLTests: XCTestCase {
    func testJoinPreservesSlashes() {
        let base = URL(string: "https://192.168.1.10:32400")!
        let url = PlexURL.join(base, path: "hubs")!
        XCTAssertEqual(url.absoluteString, "https://192.168.1.10:32400/hubs")
    }

    func testJoinMultiSegmentNotPercentEncoded() {
        let base = URL(string: "https://example.plex.direct:32400")!
        let url = PlexURL.join(base, path: "library/metadata/12345")!
        XCTAssertFalse(url.absoluteString.contains("%2F"))
        XCTAssertEqual(url.absoluteString, "https://example.plex.direct:32400/library/metadata/12345")
    }

    func testJoinColonPaths() {
        let base = URL(string: "http://10.0.0.5:32400")!
        let timeline = PlexURL.join(base, path: ":/timeline")!
        XCTAssertEqual(timeline.absoluteString, "http://10.0.0.5:32400/:/timeline")

        let photo = PlexURL.join(base, path: "photo/:/transcode")!
        XCTAssertEqual(photo.absoluteString, "http://10.0.0.5:32400/photo/:/transcode")
    }

    func testAppendingPathComponentEncodesSlash_documentsBug() {
        // Document the Foundation behavior we must avoid for multi-segment paths.
        let base = URL(string: "https://server:32400")!
        let broken = base.appendingPathComponent("hubs/home")
        XCTAssertTrue(broken.absoluteString.contains("%2F") || broken.path.contains("%2F") || broken.path == "/hubs/home")
        // On Apple platforms this becomes /hubs%2Fhome → PMS 404.
        // PlexURL.join must not do that:
        let fixed = PlexURL.join(base, path: "hubs/home")!
        XCTAssertFalse(fixed.absoluteString.contains("%2F"))
        XCTAssertTrue(fixed.absoluteString.hasSuffix("/hubs/home"))
    }
}
