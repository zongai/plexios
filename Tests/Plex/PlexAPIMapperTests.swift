import XCTest
@testable import PlexiOS

final class PlexAPIMapperTests: XCTestCase {
    func testMapLibrary() {
        let dto = APIDirectory(
            key: "1",
            uuid: "abc",
            type: "movie",
            title: "Movies",
            agent: nil,
            scanner: nil,
            thumb: nil,
            art: nil,
            count: 42,
            updatedAt: nil
        )
        let lib = PlexAPIMapper.library(from: dto)
        XCTAssertEqual(lib?.title, "Movies")
        XCTAssertEqual(lib?.type, .movie)
        XCTAssertEqual(lib?.count, 42)
    }

    func testMapConnectionRank() {
        let localHTTPS = PlexConnection(
            uri: "https://192.168.1.5:32400",
            address: "192.168.1.5",
            port: 32400,
            protocolName: "https",
            local: true,
            relay: false,
            ipv6: false
        )
        let relay = PlexConnection(
            uri: "https://relay.example",
            address: nil,
            port: 443,
            protocolName: "https",
            local: false,
            relay: true,
            ipv6: false
        )
        XCTAssertLessThan(localHTTPS.rankScore, relay.rankScore)
    }

    func testMapMetadataMinimal() {
        let dto = APIMetadata(
            ratingKey: "100",
            key: "/library/metadata/100",
            type: "movie",
            title: "Test Movie",
            summary: "A summary",
            year: 2024,
            contentRating: nil,
            rating: 8.5,
            audienceRating: nil,
            duration: 7_200_000,
            viewOffset: 120_000,
            viewCount: 0,
            lastViewedAt: nil,
            originallyAvailableAt: nil,
            thumb: nil,
            art: nil,
            parentThumb: nil,
            grandparentThumb: nil,
            parentTitle: nil,
            grandparentTitle: nil,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            index: nil,
            parentIndex: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            childCount: nil,
            studio: nil,
            tagline: nil,
            genre: [APITag(tag: "Action")],
            director: nil,
            writer: nil,
            role: nil,
            media: nil
        )
        let meta = PlexAPIMapper.metadata(from: dto)
        XCTAssertEqual(meta?.title, "Test Movie")
        XCTAssertEqual(meta?.type, .movie)
        XCTAssertTrue(meta?.isInProgress == true)
        XCTAssertEqual(meta?.genres, ["Action"])
    }

    func testResourceIsServer() {
        let server = APIResource(
            name: "Home",
            product: "Plex Media Server",
            productVersion: "1.40",
            platform: "Linux",
            clientIdentifier: "abc123",
            provides: "server",
            accessToken: "tok",
            owned: true,
            home: false,
            publicAddress: nil,
            connections: nil
        )
        XCTAssertTrue(server.isServer)
        let mapped = PlexAPIMapper.server(from: server)
        XCTAssertEqual(mapped?.machineIdentifier, "abc123")
        XCTAssertEqual(mapped?.accessToken, "tok")
    }
}
