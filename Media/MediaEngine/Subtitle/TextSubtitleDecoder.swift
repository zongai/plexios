import Foundation

enum SubtitleDecoderError: Error, LocalizedError {
    case unsupportedFormat(String)
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let f): return "Unsupported subtitle format: \(f)"
        case .parseFailed(let s): return "Subtitle parse failed: \(s)"
        }
    }
}

protocol SubtitleDecoder: AnyObject {
    var format: SubtitleFormat { get }
    func decode(data: Data, encoding: String.Encoding) throws -> [TimedSubtitle]
    /// Incremental packet from demux (may be a full file or fragment).
    func decode(packet: MediaPacket) throws -> [TimedSubtitle]
}

/// SRT + WebVTT + basic ASS/SSA text events.
final class TextSubtitleDecoder: SubtitleDecoder {
    let format: SubtitleFormat

    init(format: SubtitleFormat) {
        self.format = format
    }

    func decode(data: Data, encoding: String.Encoding = .utf8) throws -> [TimedSubtitle] {
        guard let text = String(data: data, encoding: encoding)
                ?? String(data: data, encoding: .isoLatin1)
        else {
            throw SubtitleDecoderError.parseFailed("encoding")
        }
        switch format {
        case .srt:
            return Self.parseSRT(text)
        case .webvtt:
            return Self.parseWebVTT(text)
        case .ass, .ssa:
            return Self.parseASS(text)
        case .unknown:
            throw SubtitleDecoderError.unsupportedFormat("unknown")
        }
    }

    func decode(packet: MediaPacket) throws -> [TimedSubtitle] {
        try decode(data: packet.data)
    }

    // MARK: - SRT

    static func parseSRT(_ text: String) -> [TimedSubtitle] {
        var results: [TimedSubtitle] = []
        let blocks = text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        for block in blocks {
            let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            guard lines.count >= 2 else { continue }
            var idx = 0
            // Optional numeric index
            if lines[0].trimmingCharacters(in: .whitespaces).allSatisfy(\.isNumber) {
                idx = 1
            }
            guard idx < lines.count else { continue }
            let timing = lines[idx]
            guard let (start, end) = parseSRTTiming(timing) else { continue }
            let body = lines[(idx + 1)...].joined(separator: "\n")
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            results.append(TimedSubtitle(startMs: start, endMs: end, text: body))
        }
        return results
    }

    private static func parseSRTTiming(_ line: String) -> (Int64, Int64)? {
        // 00:00:01,000 --> 00:00:04,000
        let parts = line.components(separatedBy: "-->")
        guard parts.count == 2 else { return nil }
        guard let s = parseTimestamp(parts[0].trimmingCharacters(in: .whitespaces), fractionalSep: ","),
              let e = parseTimestamp(parts[1].trimmingCharacters(in: .whitespaces), fractionalSep: ",")
        else { return nil }
        return (s, e)
    }

    // MARK: - WebVTT

    static func parseWebVTT(_ text: String) -> [TimedSubtitle] {
        var results: [TimedSubtitle] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.first?.hasPrefix("WEBVTT") == true {
            lines.removeFirst()
        }
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            if line.isEmpty { i += 1; continue }
            // Skip NOTE / STYLE blocks
            if line.hasPrefix("NOTE") || line.hasPrefix("STYLE") || line.hasPrefix("REGION") {
                while i < lines.count, !lines[i].isEmpty { i += 1 }
                continue
            }
            var timingLine = line
            if !line.contains("-->"), i + 1 < lines.count {
                // cue identifier
                i += 1
                timingLine = lines[i]
            }
            if let (start, end) = parseWebVTTTiming(timingLine) {
                i += 1
                var body: [String] = []
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                    body.append(lines[i])
                    i += 1
                }
                let textBody = body.joined(separator: "\n")
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !textBody.isEmpty {
                    results.append(TimedSubtitle(startMs: start, endMs: end, text: textBody))
                }
            } else {
                i += 1
            }
        }
        return results
    }

    private static func parseWebVTTTiming(_ line: String) -> (Int64, Int64)? {
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 2 else { return nil }
        let startStr = parts[0].trimmingCharacters(in: .whitespaces)
        let endStr = parts[1].split(separator: " ").first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard let s = parseTimestamp(startStr, fractionalSep: "."),
              let e = parseTimestamp(endStr, fractionalSep: ".")
        else { return nil }
        return (s, e)
    }

    // MARK: - ASS/SSA (Dialogue lines only)

    static func parseASS(_ text: String) -> [TimedSubtitle] {
        var results: [TimedSubtitle] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n").map(String.init)
        var formatFields: [String] = []
        for line in lines {
            if line.hasPrefix("Format:") {
                formatFields = line.dropFirst(7).split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
            }
            guard line.hasPrefix("Dialogue:") else { continue }
            let payload = String(line.dropFirst("Dialogue:".count)).trimmingCharacters(in: .whitespaces)
            // ASS: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
            let cols = splitASSColumns(payload, expected: max(formatFields.count, 10))
            let startIdx = formatFields.firstIndex(of: "Start") ?? 1
            let endIdx = formatFields.firstIndex(of: "End") ?? 2
            let textIdx = formatFields.firstIndex(of: "Text") ?? (cols.count - 1)
            let styleIdx = formatFields.firstIndex(of: "Style")
            guard cols.count > max(startIdx, endIdx, textIdx) else { continue }
            guard let start = parseASSTime(cols[startIdx]),
                  let end = parseASSTime(cols[endIdx])
            else { continue }
            var body = cols[textIdx]
            // Strip simple override tags {\...}
            body = body.replacingOccurrences(of: "\\{[^}]*\\}", with: "", options: .regularExpression)
            body = body.replacingOccurrences(of: "\\N", with: "\n")
            body = body.replacingOccurrences(of: "\\n", with: "\n")
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { continue }
            let style = styleIdx.flatMap { cols.indices.contains($0) ? cols[$0] : nil }
            results.append(TimedSubtitle(
                startMs: start,
                endMs: end,
                text: body,
                alignment: nil,
                styleName: style
            ))
        }
        return results
    }

    private static func splitASSColumns(_ line: String, expected: Int) -> [String] {
        var parts: [String] = []
        var current = ""
        var count = 0
        for ch in line {
            if ch == ",", count < expected - 1 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                count += 1
            } else {
                current.append(ch)
            }
        }
        parts.append(current.trimmingCharacters(in: .whitespaces))
        return parts
    }

    private static func parseASSTime(_ s: String) -> Int64? {
        // H:MM:SS.cs (centiseconds)
        let t = s.trimmingCharacters(in: .whitespaces)
        let parts = t.split(separator: ":")
        guard parts.count == 3 else { return nil }
        guard let h = Int64(parts[0]),
              let m = Int64(parts[1])
        else { return nil }
        let secParts = parts[2].split(separator: ".")
        guard let sec = Int64(secParts[0]) else { return nil }
        let cs: Int64 = secParts.count > 1 ? Int64(secParts[1].padding(toLength: 2, withPad: "0", startingAt: 0).prefix(2)) ?? 0 : 0
        return ((h * 3600) + (m * 60) + sec) * 1000 + cs * 10
    }

    /// Supports HH:MM:SS.mmm or MM:SS.mmm
    private static func parseTimestamp(_ raw: String, fractionalSep: Character) -> Int64? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Drop cue settings after timestamp in WebVTT end already stripped
        if let space = s.firstIndex(of: " ") {
            s = String(s[..<space])
        }
        let normalized = s.replacingOccurrences(of: String(fractionalSep), with: ".")
        let parts = normalized.split(separator: ":")
        guard parts.count == 2 || parts.count == 3 else { return nil }
        let hour: Int64
        let minute: Int64
        let secPart: Substring
        if parts.count == 3 {
            guard let h = Int64(parts[0]), let m = Int64(parts[1]) else { return nil }
            hour = h; minute = m; secPart = parts[2]
        } else {
            guard let m = Int64(parts[0]) else { return nil }
            hour = 0; minute = m; secPart = parts[1]
        }
        let secBits = secPart.split(separator: ".")
        guard let sec = Int64(secBits[0]) else { return nil }
        var ms: Int64 = 0
        if secBits.count > 1 {
            let frac = String(secBits[1].prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0)
            ms = Int64(frac) ?? 0
        }
        return ((hour * 3600) + (minute * 60) + sec) * 1000 + ms
    }
}

enum SubtitleDecoderFactory {
    static func make(format: SubtitleFormat) throws -> any SubtitleDecoder {
        switch format {
        case .srt, .webvtt, .ass, .ssa:
            return TextSubtitleDecoder(format: format)
        case .unknown:
            throw SubtitleDecoderError.unsupportedFormat("unknown")
        }
    }
}
