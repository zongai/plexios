import Foundation

/// XMLTV parser using Foundation XMLParser. Uses zlib-based gzip/zlib inflate.
enum XMLTVParser {
    static func parse(data: Data) throws -> [EPGProgram] {
        let payload = GzipDecompressor.decompressIfNeeded(data)
        // Sanity: must look like XML
        if let head = String(data: payload.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !head.isEmpty,
           !head.hasPrefix("<"),
           !head.hasPrefix("<?xml") {
            throw IPTVError.downloadFailed("EPG payload is not XML after decompress")
        }

        let delegate = XMLTVDelegate()
        let parser = XMLParser(data: payload)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw IPTVError.downloadFailed(parser.parserError?.localizedDescription ?? "XMLTV parse failed")
        }
        return delegate.programs
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
