import XCTest
@testable import PlexiOS

final class LogRedactionTests: XCTestCase {
    func testRedactsQueryToken() {
        let input = "https://plex.example.com/library/sections?X-Plex-Token=abc123secret&foo=bar"
        let output = LogRedaction.redact(input)
        XCTAssertFalse(output.contains("abc123secret"))
        XCTAssertTrue(output.contains("[REDACTED]"))
        XCTAssertTrue(output.contains("foo=bar"))
    }

    func testRedactsHeaderStyle() {
        let input = "X-Plex-Token: supersecrettoken"
        let output = LogRedaction.redact(input)
        XCTAssertFalse(output.contains("supersecrettoken"))
        XCTAssertTrue(output.contains("[REDACTED]"))
    }

    func testLeavesCleanURLAlone() {
        let input = "https://plex.example.com/library/sections?limit=20"
        let output = LogRedaction.redact(input)
        XCTAssertEqual(output, input)
    }
}
