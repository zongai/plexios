import XCTest
@testable import PlexiOS

final class HTTPClientTests: XCTestCase {
    func testHTTPClientErrorDescriptions() {
        XCTAssertEqual(HTTPClient.HTTPClientError.invalidURL.errorDescription, "Invalid URL")
        XCTAssertEqual(HTTPClient.HTTPClientError.httpStatus(404, nil).errorDescription, "HTTP 404")
    }
}
