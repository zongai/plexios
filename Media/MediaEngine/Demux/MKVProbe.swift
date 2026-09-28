import Foundation

/// EBML header detection for Matroska/WebM (not full track parse without FFmpeg).
struct MKVProbe: Sendable {
    struct Result: Sendable {
        var isEBML: Bool
        var likelyWebM: Bool
        var likelyMatroska: Bool
        var docType: String?
    }

    func probe(dataSource: HTTPRangeDataSource) async throws -> Result {
        let data = try await dataSource.read(offset: 0, length: 4096)
        // EBML header ID: 0x1A45DFA3
        guard data.count >= 4 else {
            return Result(isEBML: false, likelyWebM: false, likelyMatroska: false, docType: nil)
        }
        let isEBML = data[0] == 0x1A && data[1] == 0x45 && data[2] == 0xDF && data[3] == 0xA3
        guard isEBML else {
            return Result(isEBML: false, likelyWebM: false, likelyMatroska: false, docType: nil)
        }
        // Search for DocType string "webm" or "matroska" in first 4KB
        let ascii = String(data: data, encoding: .isoLatin1) ?? ""
        let webm = ascii.contains("webm")
        let mkv = ascii.contains("matroska")
        return Result(
            isEBML: true,
            likelyWebM: webm,
            likelyMatroska: mkv || !webm,
            docType: webm ? "webm" : (mkv ? "matroska" : "ebml")
        )
    }
}
