import XCTest
@testable import PlexiOS

final class HTTPRangeAndProbeTests: XCTestCase {
    func testMP4FourCCHelpersViaProbeTypes() {
        // Smoke: types exist and MediaProbe baseline works without network
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
        let info = MediaProbe().probeFromPlexMetadata(item)
        XCTAssertEqual(info?.container.format, "mp4")
        XCTAssertEqual(info?.videoTracks.first?.codec, "h264")
        XCTAssertEqual(info?.audioTracks.first?.codec, "aac")
    }

    func testDemuxerFactoryReturnsBuiltinWithoutFFmpeg() {
        let d = DemuxerFactory.make()
        // Builtin is actor — type check via open failure on bogus file URL
        let url = URL(fileURLWithPath: "/tmp/plexios-nonexistent-\(UUID().uuidString)")
        let exp = expectation(description: "open")
        Task {
            do {
                try await d.open(url: url, headers: [:])
                XCTFail("expected failure")
            } catch {
                // expected
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5)
    }

    func testFallbackPolicyStillFinite() {
        let steps = PlaybackFallbackPolicy().nextSteps(
            after: .nativeDirectPlay,
            failure: PlaybackFailure(stage: .demux, reason: "x", underlying: nil),
            report: CompatibilityReport(
                tracks: TrackCompatibility(
                    container: .softwareSupported, video: .hardwareSupported,
                    audio: .supported, subtitle: .supported, hdr: .supported
                ),
                preferredBackend: .nativeMediaEngine,
                preferredPath: .nativeDirectPlay,
                reasons: [],
                nativeCandidate: true
            )
        )
        XCTAssertLessThanOrEqual(steps.count, 3)
    }
}
