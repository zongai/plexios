import XCTest
@testable import PlexiOS

/// Covers robust M3U pairing + channel vs source aggregation rules.
final class M3UAggregationTests: XCTestCase {

    private let playlistId = UUID()

    // a) 3 channels × 9 sources, tvg-id always 1...9 → 3 channels, 9 sources each
    func testThreeChannelsNineSourcesSharedTvgIds() {
        var lines = ["#EXTM3U"]
        let names = ["北京卫视4K", "东方卫视4K", "深圳卫视4K"]
        for name in names {
            for id in 1...9 {
                lines.append(
                    #"#EXTINF:-1 tvg-id="\#(id)" tvg-name="\#(name)" tvg-logo="https://logo/\#(name).png" group-title="4K频道",\#(name)"#
                )
                lines.append("http://10.0.0.\(id)/hls/\(name.utf8.count)/\(id)/index.m3u8")
            }
        }
        let result = M3UParser.parse(text: lines.joined(separator: "\n"))
        XCTAssertEqual(result.entries.count, 27)

        let channels = ChannelNormalizer.channels(from: result.entries, playlistId: playlistId)
        XCTAssertEqual(channels.count, 3, "Must aggregate to 3 channels, not 27")
        for ch in channels {
            XCTAssertEqual(ch.sources.count, 9, ch.name)
            // tvg-id 1...9 is shared across channels → untrusted
            XCTAssertNil(ch.tvgID, "Shared sequential tvg-id must not be trusted: \(ch.name)")
        }
        let set = Set(channels.map(\.name))
        XCTAssertEqual(set, Set(names))
    }

    // b) Duplicate URLs within same channel dedupe
    func testDuplicateURLDedup() {
        var lines = ["#EXTM3U"]
        for id in 1...9 {
            lines.append(#"#EXTINF:-1 tvg-id="\#(id)" tvg-name="深圳卫视4K" group-title="4K",深圳卫视4K"#)
            lines.append("http://example.com/sz/\(id).m3u8")
            // duplicate of same URL
            lines.append(#"#EXTINF:-1 tvg-id="\#(id)" tvg-name="深圳卫视4K" group-title="4K",深圳卫视4K"#)
            lines.append("http://example.com/sz/\(id).m3u8")
        }
        let result = M3UParser.parse(text: lines.joined(separator: "\n"))
        XCTAssertEqual(result.entries.count, 18)
        let channels = ChannelNormalizer.channels(from: result.entries, playlistId: playlistId)
        XCTAssertEqual(channels.count, 1)
        XCTAssertEqual(channels[0].sources.count, 9)
    }

    // c) EXTVLCOPT between EXTINF and URL
    func testExtVlcOptBetweenInfAndURL() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-name="TestCH" group-title="G",TestCH
        #EXTVLCOPT:http-user-agent=Mozilla/5.0
        #EXTVLCOPT:http-referrer=https://ref.example/
        http://stream.example/live.m3u8
        """
        let result = M3UParser.parse(text: text)
        XCTAssertEqual(result.entries.count, 1)
        let e = result.entries[0]
        XCTAssertEqual(e.headers["User-Agent"], "Mozilla/5.0")
        XCTAssertEqual(e.headers["Referer"], "https://ref.example/")
        XCTAssertEqual(e.streamURL.host, "stream.example")
        XCTAssertFalse(e.opts.isEmpty)
    }

    // d) Comma inside quoted attribute / name
    func testCommaInsideQuotes() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-name="News, Weather" group-title="A, B",Display, Name
        http://a.example/1.m3u8
        """
        let result = M3UParser.parse(text: text)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].tvgName, "News, Weather")
        XCTAssertEqual(result.entries[0].groupTitle, "A, B")
        XCTAssertEqual(result.entries[0].name, "Display, Name")
    }

    // e) Trailing EXTINF without URL
    func testTrailingExtInfWithoutURL() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-name="OK" group-title="G",OK
        http://ok.example/live.m3u8
        #EXTINF:-1 tvg-name="Broken" group-title="G",Broken
        """
        let result = M3UParser.parse(text: text)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries[0].tvgName, "OK")
    }

    // f) Trusted vs untrusted tvg-id
    func testTvgIdTrustedWhenUniqueAndConsistent() {
        // Unique ids per channel, consistent across sources → trusted
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="bj" tvg-name="北京卫视" group-title="卫视",北京卫视
        http://a/1.m3u8
        #EXTINF:-1 tvg-id="bj" tvg-name="北京卫视" group-title="卫视",北京卫视
        http://b/1.m3u8
        #EXTINF:-1 tvg-id="df" tvg-name="东方卫视" group-title="卫视",东方卫视
        http://c/1.m3u8
        """
        let result = M3UParser.parse(text: text)
        let channels = ChannelNormalizer.channels(from: result.entries, playlistId: playlistId)
        XCTAssertEqual(channels.count, 2)
        let bj = channels.first { $0.name == "北京卫视" }
        let df = channels.first { $0.name == "东方卫视" }
        XCTAssertEqual(bj?.tvgID, "bj")
        XCTAssertEqual(df?.tvgID, "df")
        XCTAssertEqual(bj?.sources.count, 2)
    }

    func testTvgIdUntrustedWhenReusedAcrossChannels() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="1" tvg-name="北京卫视4K" group-title="4K频道",北京卫视4K
        http://a/1.m3u8
        #EXTINF:-1 tvg-id="1" tvg-name="东方卫视4K" group-title="4K频道",东方卫视4K
        http://b/1.m3u8
        """
        let channels = ChannelNormalizer.channels(
            from: M3UParser.parse(text: text).entries,
            playlistId: playlistId
        )
        XCTAssertEqual(channels.count, 2)
        XCTAssertNil(channels[0].tvgID)
        XCTAssertNil(channels[1].tvgID)
    }

    func testDefaultDoesNotMergeAcrossGroups() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-name="CCTV1" group-title="央视",CCTV1
        http://a/1.m3u8
        #EXTINF:-1 tvg-name="CCTV1" group-title="备用",CCTV1
        http://b/1.m3u8
        """
        let entries = M3UParser.parse(text: text).entries
        let separate = ChannelNormalizer.channels(from: entries, playlistId: playlistId)
        XCTAssertEqual(separate.count, 2)

        let merged = ChannelNormalizer.channels(
            from: entries,
            playlistId: playlistId,
            options: .init(mergeAcrossGroups: true)
        )
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].sources.count, 2)
    }

    func testBeijingAndDongfangExampleFromSpec() {
        let text = """
        #EXTM3U
        #EXTINF:-1 tvg-id="1" tvg-name="北京卫视4K" tvg-logo="https://example/北京卫视4K.png" group-title="4K频道",北京卫视4K
        http://110.72.87.182:808/hls/137/index.m3u8
        #EXTINF:-1 tvg-id="2" tvg-name="北京卫视4K" tvg-logo="https://example/北京卫视4K.png" group-title="4K频道",北京卫视4K
        http://110.72.79.250:808/hls/137/index.m3u8
        #EXTINF:-1 tvg-id="1" tvg-name="东方卫视4K" tvg-logo="https://example/东方卫视4K.png" group-title="4K频道",东方卫视4K
        http://110.72.87.182:808/hls/29/index.m3u8
        """
        let channels = ChannelNormalizer.channels(
            from: M3UParser.parse(text: text).entries,
            playlistId: playlistId
        )
        XCTAssertEqual(channels.count, 2)
        let bj = channels.first { $0.name == "北京卫视4K" }
        let df = channels.first { $0.name == "东方卫视4K" }
        XCTAssertEqual(bj?.sources.count, 2)
        XCTAssertEqual(df?.sources.count, 1)
        XCTAssertEqual(bj?.logoURLString, "https://example/北京卫视4K.png")
        XCTAssertNil(bj?.tvgID)
        XCTAssertNil(df?.tvgID)
    }
}
