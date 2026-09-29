import Foundation
import Compression

/// XMLTV parser using Foundation XMLParser. Supports plain XML; gzip payloads
/// are decompressed when the gzip magic header is present.
enum XMLTVParser {
    static func parse(data: Data) throws -> [EPGProgram] {
        let payload = decompressIfNeeded(data)
        let delegate = XMLTVDelegate()
        let parser = XMLParser(data: payload)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw IPTVError.downloadFailed(parser.parserError?.localizedDescription ?? "XMLTV parse failed")
        }
        return delegate.programs
    }

    private static func decompressIfNeeded(_ data: Data) -> Data {
        guard data.count > 10, data[0] == 0x1f, data[1] == 0x8b else {
            return data
        }
        if let inflated = simpleGunzip(data) {
            return inflated
        }
        return data
    }

    private static func simpleGunzip(_ data: Data) -> Data? {
        guard data.count > 18 else { return nil }
        var offset = 10
        let flags = data[3]
        if flags & 0x04 != 0 {
            guard offset + 2 <= data.count else { return nil }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        if flags & 0x08 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x10 != 0 {
            while offset < data.count && data[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 {
            offset += 2
        }
        guard offset + 8 < data.count else { return nil }
        let deflate = data.subdata(in: offset..<(data.count - 8))
        return inflateRaw(deflate)
    }

    private static func inflateRaw(_ data: Data) -> Data? {
        data.withUnsafeBytes { srcPtr -> Data? in
            guard let base = srcPtr.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let dstCapacity = max(data.count * 16, 256 * 1024)
            var dst = [UInt8](repeating: 0, count: dstCapacity)
            let written = compression_decode_buffer(
                &dst,
                dstCapacity,
                base,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
            guard written > 0 else { return nil }
            return Data(dst.prefix(written))
        }
    }
}

private final class XMLTVDelegate: NSObject, XMLParserDelegate {
    var programs: [EPGProgram] = []

    private var currentChannelId: String?
    private var start: Date?
    private var end: Date?
    private var title = ""
    private var subtitle: String?
    private var desc: String?
    private var category: String?
    private var icon: String?
    private var textBuffer = ""

    private static let xmltvFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyyMMddHHmmss Z"
        return f
    }()

    private static let xmltvFormatterNoTZ: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMddHHmmss"
        return f
    }()

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        textBuffer = ""
        let el = elementName.lowercased()
        if el == "programme" {
            currentChannelId = attributeDict["channel"]
            start = Self.parseXMLTVDate(attributeDict["start"])
            end = Self.parseXMLTVDate(attributeDict["stop"] ?? attributeDict["end"])
            title = ""
            subtitle = nil
            desc = nil
            category = nil
            icon = nil
        } else if el == "icon" {
            icon = attributeDict["src"] ?? icon
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.lowercased()
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "title":
            if !text.isEmpty { title = text }
        case "sub-title", "subtitle":
            if !text.isEmpty { subtitle = text }
        case "desc", "description":
            if !text.isEmpty { desc = text }
        case "category":
            if !text.isEmpty { category = text }
        case "programme":
            if let ch = currentChannelId, let s = start, let e = end, !title.isEmpty {
                let id = "\(ch)|\(Int(s.timeIntervalSince1970))|\(title.prefix(32))"
                programs.append(
                    EPGProgram(
                        id: id,
                        channelID: ch,
                        title: title,
                        subtitle: subtitle,
                        description: desc,
                        startTime: s,
                        endTime: e,
                        category: category,
                        iconURLString: icon
                    )
                )
            }
            currentChannelId = nil
        default:
            break
        }
        textBuffer = ""
    }

    private static func parseXMLTVDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.count >= 14 {
            let digits = String(s.prefix(14))
            let rest = s.dropFirst(14).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty {
                let combined = digits + " " + rest
                if let d = xmltvFormatter.date(from: combined) { return d }
            }
            return xmltvFormatterNoTZ.date(from: digits)
        }
        return nil
    }
}
