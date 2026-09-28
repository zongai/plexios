import XCTest
@testable import PlexiOS

final class ResponseCacheTests: XCTestCase {
    func testStoreAndRetrieve() async throws {
        let cache = ResponseCache(namespace: "tests-\(UUID().uuidString)")
        let value = ["a", "b", "c"]
        await cache.store(value, forKey: "k1", ttl: 60)
        let loaded: [String]? = await cache.value(forKey: "k1")
        XCTAssertEqual(loaded, value)
    }

    func testExpiry() async throws {
        let cache = ResponseCache(namespace: "tests-expire-\(UUID().uuidString)")
        await cache.store("x", forKey: "k", ttl: 0)
        // ttl 0 → immediately expired
        let loaded: String? = await cache.value(forKey: "k")
        XCTAssertNil(loaded)
    }
}
