import XCTest
@testable import PlexiOS

final class PlaybackDecisionTests: XCTestCase {
    private func movie(
        container: String,
        videoCodec: String,
        audioCodec: String,
        bitrate: Int = 8000,
        subs: [PlexStream] = []
    ) -> PlexMetadata {
        let video = PlexStream(
            id: 1, streamType: .video, codec: videoCodec, format: nil,
            language: nil, languageCode: nil, displayTitle: nil,
            extendedDisplayTitle: nil, title: nil,
            isDefault: true, isForced: false, isSelected: true, isExternal: false,
            bitrate: bitrate, channels: nil, key: nil, bitDepth: 8
        )
        let audio = PlexStream(
            id: 2, streamType: .audio, codec: audioCodec, format: nil,
            language: "English", languageCode: "en", displayTitle: "English",
            extendedDisplayTitle: nil, title: nil,
            isDefault: true, isForced: false, isSelected: true, isExternal: false,
            bitrate: 192, channels: 2, key: nil, bitDepth: nil
        )
        var streams = [video, audio]
        streams.append(contentsOf: subs)
        let part = PlexPart(
            id: 10, key: "/library/parts/10/file.\(container)",
            duration: 7_200_000, size: 1_000_000_000, container: container,
            file: nil, accessible: true, streams: streams
        )
        let media = PlexMedia(
            id: 1, duration: 7_200_000, bitrate: bitrate,
            width: 1920, height: 1080,
            videoCodec: videoCodec, audioCodec: audioCodec, container: container,
            videoResolution: "1080", videoFrameRate: "24p", videoProfile: "high",
            audioChannels: 2, parts: [part]
        )
        return PlexMetadata(
            ratingKey: "100", key: "/library/metadata/100", type: .movie,
            title: "Test", summary: nil, year: 2024, contentRating: nil,
            rating: nil, audienceRating: nil, userRating: nil, duration: 7_200_000,
            viewOffset: nil, viewCount: nil, lastViewedAt: nil,
            originallyAvailableAt: nil, thumb: nil, art: nil,
            parentThumb: nil, grandparentThumb: nil, parentTitle: nil,
            grandparentTitle: nil, parentRatingKey: nil, grandparentRatingKey: nil,
            index: nil, parentIndex: nil, librarySectionID: nil, librarySectionTitle: nil, leafCount: nil, viewedLeafCount: nil,
            childCount: nil, studio: nil, tagline: nil,
            genres: [], directors: [], writers: [], actors: [], media: [media]
        )
    }

    func testDirectPlayMP4H264AAC() {
        let item = movie(container: "mp4", videoCodec: "h264", audioCodec: "aac")
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        XCTAssertEqual(decision.mode, .directPlay)
        XCTAssertTrue(decision.reason.contains("supported natively"))
    }

    func testDirectStreamMKV() {
        let item = movie(container: "mkv", videoCodec: "h264", audioCodec: "aac")
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        XCTAssertEqual(decision.mode, .directStream)
        XCTAssertTrue(decision.reason.lowercased().contains("container") || decision.reason.contains("remux"))
    }

    func testTranscodeUnsupportedVideo() {
        let item = movie(container: "mkv", videoCodec: "vc1", audioCodec: "aac")
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        XCTAssertEqual(decision.mode, .transcode)
        XCTAssertTrue(decision.reason.contains("video codec"))
    }

    func testBitrateCapForcesTranscode() {
        let item = movie(container: "mp4", videoCodec: "h264", audioCodec: "aac", bitrate: 20000)
        var prefs = PlaybackPreferences.default
        prefs.maxVideoBitrateKbps = 4000
        let decision = PlaybackDecisionEngine(preferences: prefs)
            .decide(metadata: item, network: .lan)
        XCTAssertEqual(decision.mode, .transcode)
        XCTAssertTrue(decision.reason.contains("Quality limited"))
    }

    /// VP9 + OPUS is common (YouTube-style / WebM). AVPlayer cannot decode VP9 → must transcode.
    func testVP9OpusForcesTranscode() {
        let item = movie(container: "webm", videoCodec: "vp9", audioCodec: "opus", bitrate: 2340)
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        XCTAssertEqual(decision.mode, .transcode)
        XCTAssertTrue(
            decision.reason.lowercased().contains("vp9")
                || decision.reason.lowercased().contains("video codec")
                || decision.reason.lowercased().contains("opus"),
            "Expected codec reason, got: \(decision.reason)"
        )
    }

    func testOpusAudioAloneForcesTranscodeOrRemux() {
        // H.264 video is fine but OPUS audio is not native → not Direct Play
        let item = movie(container: "mp4", videoCodec: "h264", audioCodec: "opus")
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        XCTAssertNotEqual(decision.mode, .directPlay)
        XCTAssertTrue(decision.mode == .transcode || decision.mode == .directStream)
    }

    func testPGSBurnIn() {
        let sub = PlexStream(
            id: 3, streamType: .subtitle, codec: "pgs", format: "pgs",
            language: "English", languageCode: "en", displayTitle: "English PGS",
            extendedDisplayTitle: nil, title: nil,
            isDefault: false, isForced: false, isSelected: true, isExternal: false,
            bitrate: nil, channels: nil, key: nil, bitDepth: nil
        )
        let item = movie(container: "mkv", videoCodec: "h264", audioCodec: "aac", subs: [sub])
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        // Selected PGS should force burn-in → transcode
        XCTAssertEqual(decision.mode, .transcode)
        XCTAssertTrue(decision.burnInSubtitles || decision.reason.contains("subtitle"))
    }

    func testDecisionReasonsAreNonEmpty() {
        let cases: [(String, String, String)] = [
            ("mp4", "h264", "aac"),
            ("mkv", "h264", "aac"),
            ("mkv", "vc1", "dts"),
        ]
        for (c, v, a) in cases {
            let d = PlaybackDecisionEngine().decide(
                metadata: movie(container: c, videoCodec: v, audioCodec: a),
                network: .lan
            )
            XCTAssertFalse(d.reason.isEmpty, "Reason empty for \(c)/\(v)/\(a)")
        }
    }
}


    func testAutoSelectsTextSubtitleWhenEnabled() {
        let sub = PlexStream(
            id: 3, streamType: .subtitle, codec: "webvtt", format: "webvtt",
            language: "Turkish", languageCode: "tr", displayTitle: "Turkish (auto-generated)",
            extendedDisplayTitle: nil, title: nil,
            isDefault: false, isForced: false, isSelected: false, isExternal: true,
            bitrate: nil, channels: nil, key: "/library/streams/3", bitDepth: nil
        )
        let item = movie(container: "mkv", videoCodec: "h264", audioCodec: "aac", subs: [sub])
        let decision = PlaybackDecisionEngine().decide(metadata: item, network: .lan)
        XCTAssertEqual(decision.selectedSubtitleStreamId, 3)
        XCTAssertFalse(decision.burnInSubtitles)
        // Soft sub → not pure direct play
        XCTAssertNotEqual(decision.mode, .directPlay)
    }
