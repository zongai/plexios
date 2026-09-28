import XCTest
@testable import PlexiOS

final class SubtitleDecoderTests: XCTestCase {
    func testParseSRT() throws {
        let srt = """
        1
        00:00:01,000 --> 00:00:03,000
        Hello world

        2
        00:00:04,500 --> 00:00:06,000
        Second line
        """
        let cues = TextSubtitleDecoder.parseSRT(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].startMs, 1000)
        XCTAssertEqual(cues[0].endMs, 3000)
        XCTAssertEqual(cues[0].text, "Hello world")
        XCTAssertEqual(cues[1].startMs, 4500)
    }

    func testParseWebVTT() {
        let vtt = """
        WEBVTT

        00:00:01.000 --> 00:00:02.500
        Turkish line

        00:00:03.000 --> 00:00:04.000
        Another
        """
        let cues = TextSubtitleDecoder.parseWebVTT(vtt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].text, "Turkish line")
        XCTAssertEqual(cues[0].startMs, 1000)
        XCTAssertEqual(cues[0].endMs, 2500)
    }

    func testParseASSDialogue() {
        let ass = """
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Hello{\\b1}ASS
        """
        let cues = TextSubtitleDecoder.parseASS(ass)
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues[0].startMs, 1000)
        XCTAssertEqual(cues[0].endMs, 3000)
        XCTAssertTrue(cues[0].text.contains("Hello"))
    }

    func testTrackControllerActiveWindow() throws {
        let c = SubtitleTrackController()
        c.load([
            TimedSubtitle(startMs: 1000, endMs: 2000, text: "A"),
            TimedSubtitle(startMs: 3000, endMs: 4000, text: "B")
        ])
        XCTAssertEqual(c.activeCues(atMs: 1500).map(\.text), ["A"])
        XCTAssertTrue(c.activeCues(atMs: 2500).isEmpty)
        XCTAssertEqual(c.activeCues(atMs: 3500).map(\.text), ["B"])
        c.subtitleStyle.delayMs = -500
        XCTAssertEqual(c.activeCues(atMs: 1600).map(\.text), ["A"]) // 1600-500=1100 still in A
    }

    func testFormatDetection() {
        XCTAssertEqual(SubtitleFormat.from(codecOrFormat: "webvtt"), .webvtt)
        XCTAssertEqual(SubtitleFormat.from(codecOrFormat: "srt"), .srt)
        XCTAssertEqual(SubtitleFormat.from(codecOrFormat: "ass"), .ass)
    }
}
