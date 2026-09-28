import CoreGraphics
import Foundation

enum SubtitleFormat: String, Sendable, Equatable {
    case srt
    case webvtt
    case ass
    case ssa
    case unknown

    static func from(codecOrFormat: String?) -> SubtitleFormat {
        let c = (codecOrFormat ?? "").lowercased()
        if c.contains("webvtt") || c == "vtt" { return .webvtt }
        if c.contains("srt") || c == "subrip" { return .srt }
        if c == "ass" || c.contains("advanced_ssa") { return .ass }
        if c == "ssa" { return .ssa }
        return .unknown
    }
}

struct SubtitleStyle: Sendable, Equatable {
    var fontSize: CGFloat = 42
    var fontName: String = "Helvetica"
    var primaryColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (1, 1, 1, 1)
    var outlineColor: (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) = (0, 0, 0, 0.9)
    var outlineWidth: CGFloat = 2
    var shadowOffset: CGFloat = 1
    /// Vertical placement 0 = top, 1 = bottom (default bottom).
    var verticalPosition: CGFloat = 0.92
    var delayMs: Int64 = 0
}

struct TimedSubtitle: Sendable, Equatable, Identifiable {
    var id: String { "\(startMs)-\(endMs)-\(text.hashValue)" }
    var startMs: Int64
    var endMs: Int64
    var text: String
    /// Optional ASS alignment / position hints (simplified).
    var alignment: Int?
    var styleName: String?
}

struct SubtitleCueEvent: Sendable, Equatable {
    var active: [TimedSubtitle]
    var mediaTimeMs: Int64
}
