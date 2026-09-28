import XCTest
@testable import PlexiOS

final class AuthenticationStateTests: XCTestCase {
    func testInitialUnknown() {
        // State enum equality
        let a = AuthenticationService.State.signedOut
        let b = AuthenticationService.State.signedOut
        XCTAssertEqual(a, b)

        let signing = AuthenticationService.State.signingIn(code: "ABCD", pinID: 1)
        XCTAssertNotEqual(signing, .signedOut)
    }

    func testPlexErrorAuthDescriptions() {
        XCTAssertEqual(
            PlexError.authentication(.tokenInvalid).localizedDescription,
            "Session expired — please sign in again"
        )
        XCTAssertEqual(
            PlexError.authentication(.pinExpired).localizedDescription,
            "Sign-in code expired"
        )
    }
}
