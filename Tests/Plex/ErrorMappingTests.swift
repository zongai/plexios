import XCTest
@testable import PlexiOS

final class ErrorMappingTests: XCTestCase {
    func testURLErrorOffline() {
        let err = URLError(.notConnectedToInternet)
        let mapped = ErrorMapping.map(err)
        guard case .network(.offline) = mapped else {
            return XCTFail("Expected offline, got \(mapped)")
        }
    }

    func testURLErrorTimeout() {
        let err = URLError(.timedOut)
        let mapped = ErrorMapping.map(err)
        guard case .network(.timeout) = mapped else {
            return XCTFail("Expected timeout, got \(mapped)")
        }
    }

    func testHTTP401() {
        let err = HTTPClient.HTTPClientError.httpStatus(401, nil)
        let mapped = ErrorMapping.map(err)
        guard case .authentication(.tokenInvalid) = mapped else {
            return XCTFail("Expected tokenInvalid, got \(mapped)")
        }
    }

    func testHTTP503() {
        let err = HTTPClient.HTTPClientError.httpStatus(503, nil)
        let mapped = ErrorMapping.map(err)
        guard case .serverUnavailable = mapped else {
            return XCTFail("Expected serverUnavailable, got \(mapped)")
        }
    }

    func testCancellation() {
        let mapped = ErrorMapping.map(CancellationError())
        guard case .cancelled = mapped else {
            return XCTFail("Expected cancelled")
        }
    }

    func testRecoverySuggestionOffline() {
        let suggestion = ErrorMapping.recoverySuggestion(for: .network(.offline))
        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion!.lowercased().contains("connection") || suggestion!.lowercased().contains("wi"))
    }

    func testPassthroughPlexError() {
        let original = PlexError.mediaUnavailable
        let mapped = ErrorMapping.map(original)
        guard case .mediaUnavailable = mapped else {
            return XCTFail("Should pass through")
        }
    }
}
