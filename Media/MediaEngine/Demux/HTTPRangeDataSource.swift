import Foundation

/// HTTP(S) reader with Range requests for progressive demux (no full download).
actor HTTPRangeDataSource {
    struct OpenInfo: Sendable {
        var contentLength: Int64?
        var acceptRanges: Bool
        var contentType: String?
    }

    private let session: URLSession
    private var url: URL?
    private var headers: [String: String] = [:]
    private var contentLength: Int64?
    private var acceptRanges = false

    init(session: URLSession = .shared) {
        self.session = session
    }

    func open(url: URL, headers: [String: String] = [:]) async throws -> OpenInfo {
        self.url = url
        self.headers = headers

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        // Some PMS reject HEAD — fall back to 0-0 range GET
        do {
            let (_, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse {
                parseHeaders(http)
                if http.statusCode == 200 || http.statusCode == 206 {
                    return OpenInfo(
                        contentLength: contentLength,
                        acceptRanges: acceptRanges,
                        contentType: http.value(forHTTPHeaderField: "Content-Type")
                    )
                }
            }
        } catch {
            // fall through to range probe
        }

        let probe = try await read(offset: 0, length: 1)
        _ = probe
        return OpenInfo(
            contentLength: contentLength,
            acceptRanges: acceptRanges || true,
            contentType: nil
        )
    }

    /// Read `[offset, offset + length)` via `Range: bytes=`.
    func read(offset: Int64, length: Int) async throws -> Data {
        guard let url else { throw DemuxError.notOpen }
        guard length > 0 else { return Data() }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (k, v) in headers {
            request.setValue(v, forHTTPHeaderField: k)
        }
        let end = offset + Int64(length) - 1
        request.setValue("bytes=\(offset)-\(end)", forHTTPHeaderField: "Range")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DemuxError.readFailed("Non-HTTP response")
        }
        parseHeaders(http)

        // 200 = server ignored Range and returned whole body — take prefix only
        if http.statusCode == 200 {
            if data.count > length {
                return data.prefix(length)
            }
            return data
        }
        if http.statusCode == 206 || (200...299).contains(http.statusCode) {
            return data
        }
        throw DemuxError.readFailed("HTTP \(http.statusCode)")
    }

    func totalLength() -> Int64? { contentLength }

    private func parseHeaders(_ http: HTTPURLResponse) {
        if let len = http.value(forHTTPHeaderField: "Content-Length"),
           let v = Int64(len) {
            // For 206, Content-Length is range size; prefer Content-Range total
            if http.statusCode != 206 {
                contentLength = v
            }
        }
        if let cr = http.value(forHTTPHeaderField: "Content-Range"),
           let total = cr.split(separator: "/").last,
           let v = Int64(total) {
            contentLength = v
        }
        if let ar = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased(),
           ar.contains("bytes") {
            acceptRanges = true
        }
        if http.statusCode == 206 {
            acceptRanges = true
        }
    }
}
