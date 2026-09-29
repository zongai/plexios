import Foundation

// MARK: - Parsed row (one EXTINF + URL pairing)

struct M3UEntry: Sendable, Equatable {
    var duration: TimeInterval?
    var name: String
    var tvgID: String?
    var tvgName: String?
    var tvgLogo: String?
    var groupTitle: String?
    var country: String?
    var language: String?
    var attributes: [String: String]
    var streamURL: URL
    /// HTTP headers derived from #EXTVLCOPT (and similar).
    var headers: [String: String]
    /// Raw option lines associated with this entry (for diagnostics).
    var opts: [String]
}

struct M3UParseResult: Sendable, Equatable {
    var epgURL: URL?
    var entries: [M3UEntry]
}

/// Robust EXTM3U / EXTINF parser (pure functions, state-machine pairing).
///
/// Design:
/// - `#EXTINF` opens a pending entry; the **next non-empty non-`#` line** is its URL.
/// - `#EXTVLCOPT` / `#EXTGRP` / other `#` lines between them attach to the pending entry
///   and **must not** break the pairing (no odd/even line pairing).
/// - Trailing `#EXTINF` without URL is dropped (no crash).
/// - Attributes: `key="value"` with keys lowercased; display name is after the last
///   comma that is outside quotes.
enum M3UParser {
    static func parse(data: Data) throws -> M3UParseResult {
        // Strip UTF-8 BOM if present
        var data = data
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            data = data.dropFirst(3)
        }
        guard let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else {
            throw IPTVError.invalidPlaylistEncoding
        }
        return parse(text: text)
    }

    static func parse(text: String) -> M3UParseResult {
        parseLines(normalizeNewlines(text))
    }

    // MARK: - State machine

    private struct Pending {
        var duration: TimeInterval?
        var name: String
        var attrs: [String: String]
        var headers: [String: String] = [:]
        var opts: [String] = []
    }

    static func parseLines(_ text: String) -> M3UParseResult {
        var epgURL: URL?
        var entries: [M3UEntry] = []
        var pending: Pending?

        // Split on any newline style; keep empty lines as delimiters only (skipped)
        text.enumerateLines { rawLine, _ in
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }

            // Tolerate junk before #EXTINF on the same logical start (rare)
            if let range = line.range(of: "#EXTINF:", options: .caseInsensitive) {
                line = String(line[range.lowerBound...])
            }

            let upper = line.uppercased()

            if upper.hasPrefix("#EXTM3U") {
                let attrs = parseAttributes(from: String(line.dropFirst(7)))
                if let u = attrs["url-tvg"] ?? attrs["x-tvg-url"] ?? attrs["tvg-url"] {
                    epgURL = IPTVNetwork.normalizeURL(from: u)
                }
                return
            }

            if upper.hasPrefix("#EXTINF:") {
                // New EXTINF replaces previous unfinished pending (orphan EXTINF dropped)
                let body = String(line.dropFirst("#EXTINF:".count))
                let (duration, rest) = splitDuration(body)
                let (attrs, name) = splitAttrsAndName(rest)
                pending = Pending(duration: duration, name: name, attrs: attrs)
                return
            }

            // Directive lines while pending → attach, do not close entry
            if line.hasPrefix("#") {
                if var p = pending {
                    p.opts.append(line)
                    applyDirective(line, to: &p)
                    pending = p
                }
                // Unknown # outside pending: ignore
                return
            }

            // URL line
            guard let url = IPTVNetwork.normalizeURL(from: line) else {
                // Invalid URL: drop pending pairing for this EXTINF
                pending = nil
                return
            }

            let info = pending
            let attrs = info?.attrs ?? [:]
            let display = {
                if let n = info?.name, !n.isEmpty { return n }
                return attrs["tvg-name"] ?? "Channel"
            }()

            entries.append(
                M3UEntry(
                    duration: info?.duration,
                    name: display,
                    tvgID: attrs["tvg-id"],
                    tvgName: attrs["tvg-name"],
                    tvgLogo: attrs["tvg-logo"],
                    groupTitle: attrs["group-title"] ?? attrs["extgrp"],
                    country: attrs["tvg-country"],
                    language: attrs["tvg-language"],
                    attributes: attrs,
                    streamURL: url,
                    headers: info?.headers ?? [:],
                    opts: info?.opts ?? []
                )
            )
            pending = nil
        }

        // Trailing EXTINF without URL → ignored (no crash)
        return M3UParseResult(epgURL: epgURL, entries: entries)
    }

    private static func applyDirective(_ line: String, to pending: inout Pending) {
        let upper = line.uppercased()
        if upper.hasPrefix("#EXTVLCOPT:") {
            let body = String(line.dropFirst("#EXTVLCOPT:".count))
            let lower = body.lowercased()
            if lower.hasPrefix("http-user-agent="),
               let v = body.split(separator: "=", maxSplits: 1).last {
                pending.headers["User-Agent"] = String(v)
            } else if lower.hasPrefix("http-referrer=") || lower.hasPrefix("http-referer="),
                      let v = body.split(separator: "=", maxSplits: 1).last {
                pending.headers["Referer"] = String(v)
            } else if lower.hasPrefix("http-origin="),
                      let v = body.split(separator: "=", maxSplits: 1).last {
                pending.headers["Origin"] = String(v)
            }
        } else if upper.hasPrefix("#EXTGRP:") {
            let g = String(line.dropFirst("#EXTGRP:".count)).trimmingCharacters(in: .whitespaces)
            if !g.isEmpty {
                pending.attrs["group-title"] = g
            }
        }
    }

    // MARK: - Attribute / name parsing

    /// Split duration prefix from EXTINF body.
    static func splitDuration(_ body: String) -> (TimeInterval?, String) {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        // Duration ends at first space or comma
        var i = trimmed.startIndex
        while i < trimmed.endIndex {
            let c = trimmed[i]
            if c == " " || c == "," { break }
            i = trimmed.index(after: i)
        }
        let durStr = String(trimmed[..<i])
        let rest = String(trimmed[i...]).trimmingCharacters(in: .whitespaces)
        let duration = TimeInterval(durStr)
        return (duration, rest)
    }

    /// Attributes + display name. Display name = after last comma **outside quotes**.
    static func splitAttrsAndName(_ rest: String) -> ([String: String], String) {
        // Find last comma outside double quotes
        var inQuotes = false
        var lastComma: String.Index?
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if c == "\"" { inQuotes.toggle() }
            else if c == ",", !inQuotes { lastComma = i }
            i = rest.index(after: i)
        }

        if let comma = lastComma {
            let attrPart = String(rest[..<comma])
            let name = String(rest[rest.index(after: comma)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (parseAttributes(from: attrPart), name)
        }
        // No comma → treat whole as attrs only, name empty
        return (parseAttributes(from: rest), "")
    }

    /// `key="value"` pairs; keys lowercased. Tolerates spaces around `=`.
    static func parseAttributes(from text: String) -> [String: String] {
        var result: [String: String] = [:]
        let pattern = #"([A-Za-z0-9_-]+)\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match,
                  match.numberOfRanges >= 3,
                  let keyR = Range(match.range(at: 1), in: text),
                  let valR = Range(match.range(at: 2), in: text) else { return }
            let key = String(text[keyR]).lowercased()
            result[key] = String(text[valR])
        }
        return result
    }

    // MARK: - Shared helpers for streaming parser

    static func splitDurationPublic(_ body: String) -> (TimeInterval?, String) { splitDuration(body) }
    static func splitAttrsAndNamePublic(_ rest: String) -> ([String: String], String) { splitAttrsAndName(rest) }
    static func parseAttributesPublic(from text: String) -> [String: String] { parseAttributes(from: text) }

    private static func normalizeNewlines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
