import XCTest
@testable import PlexiOS

/// Basic Keychain round-trip tests.
/// Note: Keychain behavior in Simulator / CI may require entitlements;
/// these tests validate the API surface and error paths.
final class KeychainStoreTests: XCTestCase {
    private var store: KeychainStore!
    private let testKey = "test.plexios.keychain.roundtrip"

    override func setUp() {
        super.setUp()
        store = KeychainStore(service: "com.plexios.tests")
        try? store.remove(testKey)
    }

    override func tearDown() {
        try? store.remove(testKey)
        store = nil
        super.tearDown()
    }

    func testSetGetRemove() throws {
        try store.set("secret-token-value", forKey: testKey)
        let value = try store.get(testKey)
        XCTAssertEqual(value, "secret-token-value")

        try store.remove(testKey)
        let after = try store.get(testKey)
        XCTAssertNil(after)
    }

    func testOverwrite() throws {
        try store.set("first", forKey: testKey)
        try store.set("second", forKey: testKey)
        XCTAssertEqual(try store.get(testKey), "second")
    }

    func testContains() throws {
        XCTAssertFalse(store.contains(testKey))
        try store.set("x", forKey: testKey)
        XCTAssertTrue(store.contains(testKey))
    }
}
