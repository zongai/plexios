import XCTest
@testable import PlexiOS

final class MediaModelTests: XCTestCase {
    func testProgressFraction() {
        let item = makeMetadata(viewOffset: 300_000, duration: 1_200_000)
        XCTAssertEqual(item.progressFraction, 0.25, accuracy: 0.001)
        XCTAssertTrue(item.isInProgress)
        XCTAssertFalse(item.isWatched)
    }

    func testWatchedWithoutOffset() {
        let item = makeMetadata(viewOffset: nil, duration: 1_000_000, viewCount: 2)
        XCTAssertTrue(item.isWatched)
        XCTAssertFalse(item.isInProgress)
        XCTAssertEqual(item.progressFraction, 0)
    }

    func testConnectionRankLocalPreferred() {
        let local = PlexConnection(
            uri: "https://10.0.0.1:32400", address: "10.0.0.1", port: 32400,
            protocolName: "https", local: true, relay: false, ipv6: false
        )
        let remote = PlexConnection(
            uri: "https://example.com:32400", address: "example.com", port: 32400,
            protocolName: "https", local: false, relay: false, ipv6: false
        )
        let relay = PlexConnection(
            uri: "https://relay", address: nil, port: 443,
            protocolName: "https", local: false, relay: true, ipv6: false
        )
        XCTAssertLessThan(local.rankScore, remote.rankScore)
        XCTAssertLessThan(remote.rankScore, relay.rankScore)
    }

    func testCardSubtitleMovie() {
        let item = makeMetadata(type: .movie, year: 2020)
        XCTAssertEqual(item.cardSubtitle(), "2020")
    }

    func testCardSubtitleEpisode() {
        var item = makeMetadata(type: .episode)
        // inject indices via full init
        item = PlexMetadata(
            ratingKey: "1", key: "/library/metadata/1", type: .episode,
            title: "Pilot", summary: nil, year: nil, contentRating: nil,
            rating: nil, audienceRating: nil, userRating: nil, duration: nil,
            viewOffset: nil, viewCount: nil, lastViewedAt: nil,
            originallyAvailableAt: nil, thumb: nil, art: nil,
            parentThumb: nil, grandparentThumb: nil, parentTitle: "S1",
            grandparentTitle: "Show", parentRatingKey: nil, grandparentRatingKey: nil,
            index: 1, parentIndex: 1, leafCount: nil, viewedLeafCount: nil,
            childCount: nil, studio: nil, tagline: nil,
            genres: [], directors: [], writers: [], actors: [], media: []
        )
        XCTAssertEqual(item.cardSubtitle(), "S1 · E1")
    }

    private func makeMetadata(
        type: PlexMetadataType = .movie,
        year: Int? = 2024,
        viewOffset: Int64? = nil,
        duration: Int64? = 1_000_000,
        viewCount: Int? = nil
    ) -> PlexMetadata {
        PlexMetadata(
            ratingKey: "1", key: "/library/metadata/1", type: type,
            title: "Title", summary: nil, year: year, contentRating: nil,
            rating: nil, audienceRating: nil, userRating: nil, duration: duration,
            viewOffset: viewOffset, viewCount: viewCount, lastViewedAt: nil,
            originallyAvailableAt: nil, thumb: nil, art: nil,
            parentThumb: nil, grandparentThumb: nil, parentTitle: nil,
            grandparentTitle: nil, parentRatingKey: nil, grandparentRatingKey: nil,
            index: nil, parentIndex: nil, leafCount: nil, viewedLeafCount: nil,
            childCount: nil, studio: nil, tagline: nil,
            genres: [], directors: [], writers: [], actors: [], media: []
        )
    }
}
