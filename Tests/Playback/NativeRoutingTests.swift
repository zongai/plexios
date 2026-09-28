import XCTest
@testable import PlexiOS

final class NativeRoutingTests: XCTestCase {
    func testNativeCandidateRequiresFlagAndDirectPlay() {
        let video = PlexStream(
            id: 1, streamType: .video, codec: "h264", format: nil,
            language: nil, languageCode: nil, displayTitle: nil,
            extendedDisplayTitle: nil, title: nil,
            isDefault: true, isForced: false, isSelected: true, isExternal: false,
            bitrate: 5000, channels: nil, key: nil, bitDepth: 8
        )
        let audio = PlexStream(
            id: 2, streamType: .audio, codec: "aac", format: nil,
            language: "en", languageCode: "en", displayTitle: "English",
            extendedDisplayTitle: nil, title: nil,
            isDefault: true, isForced: false, isSelected: true, isExternal: false,
            bitrate: 128, channels: 2, key: nil, bitDepth: nil
        )
        let part = PlexPart(
            id: 1, key: "/library/parts/1/file.mp4", duration: 120_000, size: 1,
            container: "mp4", file: nil, accessible: true, streams: [video, audio]
        )
        let media = PlexMedia(
            id: 1, duration: 120_000, bitrate: 5000, width: 1920, height: 1080,
            videoCodec: "h264", audioCodec: "aac", container: "mp4",
            videoResolution: "1080", videoFrameRate: "24", videoProfile: "high",
            audioChannels: 2, parts: [part]
        )
        let item = PlexMetadata(
            ratingKey: "1", key: "/library/metadata/1", type: .movie,
            title: "T", summary: nil, year: nil, contentRating: nil,
            rating: nil, audienceRating: nil, userRating: nil, duration: 120_000,
            viewOffset: nil, viewCount: nil, lastViewedAt: nil,
            originallyAvailableAt: nil, thumb: nil, art: nil,
            parentThumb: nil, grandparentThumb: nil, parentTitle: nil,
            grandparentTitle: nil, parentRatingKey: nil, grandparentRatingKey: nil,
            index: nil, parentIndex: nil, leafCount: nil, viewedLeafCount: nil,
            childCount: nil, studio: nil, tagline: nil,
            genres: [], directors: [], writers: [], actors: [], media: [media]
        )
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        XCTAssertEqual(decision.mode, .directPlay)

        let off = PlaybackCompatibilityAnalyzer(nativeEngineEnabled: false)
            .analyze(metadata: item, decision: decision, network: .lan)
        XCTAssertEqual(off.preferredBackend, .avPlayer)
        XCTAssertFalse(off.nativeCandidate)

        let on = PlaybackCompatibilityAnalyzer(nativeEngineEnabled: true)
            .analyze(metadata: item, decision: decision, network: .lan)
        XCTAssertTrue(on.nativeCandidate)
        XCTAssertEqual(on.preferredBackend, .nativeMediaEngine)
        XCTAssertEqual(on.preferredPath, .nativeDirectPlay)
    }
}
