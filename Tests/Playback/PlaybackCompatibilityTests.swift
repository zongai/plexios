import XCTest
@testable import PlexiOS

final class PlaybackCompatibilityTests: XCTestCase {
    func testVP9PrefersTranscodePathViaDecision() {
        let video = PlexStream(
            id: 1, streamType: .video, codec: "vp9", format: nil,
            language: nil, languageCode: nil, displayTitle: nil,
            extendedDisplayTitle: nil, title: nil,
            isDefault: true, isForced: false, isSelected: true, isExternal: false,
            bitrate: 2000, channels: nil, key: nil, bitDepth: 8
        )
        let audio = PlexStream(
            id: 2, streamType: .audio, codec: "opus", format: nil,
            language: "en", languageCode: "en", displayTitle: "English",
            extendedDisplayTitle: nil, title: nil,
            isDefault: true, isForced: false, isSelected: true, isExternal: false,
            bitrate: 128, channels: 2, key: nil, bitDepth: nil
        )
        let part = PlexPart(
            id: 1, key: "/library/parts/1/file.webm", duration: 60_000, size: 1,
            container: "webm", file: nil, accessible: true, streams: [video, audio]
        )
        let media = PlexMedia(
            id: 1, duration: 60_000, bitrate: 2000, width: 1920, height: 1080,
            videoCodec: "vp9", audioCodec: "opus", container: "webm",
            videoResolution: "1080", videoFrameRate: "25", videoProfile: nil,
            audioChannels: 2, parts: [part]
        )
        let item = PlexMetadata(
            ratingKey: "1", key: "/library/metadata/1", type: .movie,
            title: "VP9", summary: nil, year: nil, contentRating: nil,
            rating: nil, audienceRating: nil, userRating: nil, duration: 60_000,
            viewOffset: nil, viewCount: nil, lastViewedAt: nil,
            originallyAvailableAt: nil, thumb: nil, art: nil,
            parentThumb: nil, grandparentThumb: nil, parentTitle: nil,
            grandparentTitle: nil, parentRatingKey: nil, grandparentRatingKey: nil,
            index: nil, parentIndex: nil, librarySectionID: nil, librarySectionTitle: nil, leafCount: nil, viewedLeafCount: nil,
            childCount: nil, studio: nil, tagline: nil,
            genres: [], directors: [], writers: [], actors: [], media: [media]
        )
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        let report = PlaybackCompatibilityAnalyzer(nativeEngineEnabled: false)
            .analyze(metadata: item, decision: decision, network: .lan)
        XCTAssertEqual(report.preferredBackend, .avPlayer)
        XCTAssertFalse(report.nativeCandidate)
        XCTAssertEqual(decision.mode, .transcode)
    }

    func testFallbackFromDirectToTranscode() {
        let steps = PlaybackFallbackPolicy().nextSteps(
            after: .avPlayerDirect,
            failure: PlaybackFailure(stage: .videoDecoder, reason: "fail", underlying: nil),
            report: CompatibilityReport(
                tracks: TrackCompatibility(
                    container: .supported, video: .unsupported, audio: .supported,
                    subtitle: .supported, hdr: .supported
                ),
                preferredBackend: .avPlayer,
                preferredPath: .avPlayerDirect,
                reasons: [],
                nativeCandidate: false
            )
        )
        XCTAssertFalse(steps.isEmpty)
        XCTAssertEqual(steps.last?.path, .plexTranscode)
    }
}
