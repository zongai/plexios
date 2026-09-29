import XCTest
@testable import PlexiOS

final class PlaybackURLBuilderTests: XCTestCase {
    private let base = URL(string: "https://plex.local:32400")!
    private var builder: PlaybackURLBuilder {
        PlaybackURLBuilder(
            baseURL: base,
            token: "secret-token",
            clientIdentifier: "client-1",
            identityHeaders: ["X-Plex-Product": "Test"]
        )
    }

    private func samplePart(container: String = "mp4") -> PlexPart {
        PlexPart(
            id: 1,
            key: "/library/parts/1/file.\(container)",
            duration: 1000,
            size: 100,
            container: container,
            file: nil,
            accessible: true,
            streams: []
        )
    }

    private func sampleMetadata(part: PlexPart) -> PlexMetadata {
        let media = PlexMedia(
            id: 1, duration: 1000, bitrate: 5000,
            width: 1920, height: 1080,
            videoCodec: "h264", audioCodec: "aac", container: part.container,
            videoResolution: "1080", videoFrameRate: nil, videoProfile: nil,
            audioChannels: 2, parts: [part]
        )
        return PlexMetadata(
            ratingKey: "99", key: "/library/metadata/99", type: .movie,
            title: "T", summary: nil, year: nil, contentRating: nil,
            rating: nil, audienceRating: nil, userRating: nil, duration: 1000,
            viewOffset: nil, viewCount: nil, lastViewedAt: nil,
            originallyAvailableAt: nil, thumb: nil, art: nil,
            parentThumb: nil, grandparentThumb: nil, parentTitle: nil,
            grandparentTitle: nil, parentRatingKey: nil, grandparentRatingKey: nil,
            index: nil, parentIndex: nil, librarySectionID: nil, librarySectionTitle: nil, leafCount: nil, viewedLeafCount: nil,
            childCount: nil, studio: nil, tagline: nil,
            genres: [], directors: [], writers: [], actors: [], media: [media]
        )
    }

    func testDirectPlayURLContainsTokenAndPath() {
        let part = samplePart()
        let url = builder.directPlayURL(part: part)
        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("library/parts/1"))
        XCTAssertTrue(url!.absoluteString.contains("X-Plex-Token=secret-token"))
        XCTAssertTrue(url!.absoluteString.contains("X-Plex-Client-Identifier=client-1"))
    }

    func testTranscodeURLUsesHLSAndSession() {
        let part = samplePart(container: "mkv")
        let meta = sampleMetadata(part: part)
        let decision = PlaybackDecision(
            mode: .transcode,
            reason: "test",
            mediaIndex: 0,
            partIndex: 0,
            selectedAudioStreamId: 2,
            selectedSubtitleStreamId: nil,
            burnInSubtitles: false,
            maxBitrateKbps: 4000
        )
        let url = builder.playbackURL(
            metadata: meta,
            part: part,
            decision: decision,
            sessionId: "sess-abc",
            offsetMs: 12000,
            network: .wan
        )
        XCTAssertNotNil(url)
        let s = url!.absoluteString
        XCTAssertTrue(s.contains("video/:/transcode/universal/start.m3u8"))
        XCTAssertTrue(s.contains("session=sess-abc"))
        XCTAssertTrue(s.contains("offset=12000"))
        XCTAssertTrue(s.contains("directPlay=0"))
        XCTAssertTrue(s.contains("maxVideoBitrate=4000"))
        XCTAssertTrue(s.contains("audioStreamID=2"))
    }

    func testDirectPlayModeUsesFileURL() {
        let part = samplePart()
        let meta = sampleMetadata(part: part)
        let decision = PlaybackDecision(
            mode: .directPlay,
            reason: "ok",
            mediaIndex: 0,
            partIndex: 0,
            selectedAudioStreamId: nil,
            selectedSubtitleStreamId: nil,
            burnInSubtitles: false,
            maxBitrateKbps: nil
        )
        let url = builder.playbackURL(
            metadata: meta,
            part: part,
            decision: decision,
            sessionId: "x",
            offsetMs: 0,
            network: .lan
        )
        XCTAssertNotNil(url)
        XCTAssertFalse(url!.absoluteString.contains("transcode"))
    }
}
