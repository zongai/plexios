import Foundation

/// Generic async HTTP client. Plex-specific headers and decoding live in PlexAPIClient.
actor HTTPClient {
    private let session: URLSession
    private let logger: LogRouter

    init(session: URLSession = .shared, logger: LogRouter) {
        self.session = session
        self.logger = logger
    }

    struct Response: Sendable {
        let data: Data
        let httpResponse: HTTPURLResponse
        let statusCode: Int
    }

    enum HTTPClientError: Error, LocalizedError, Sendable {
        case invalidURL
        case nonHTTPResponse
        case httpStatus(Int, Data?)
        case transport(Error)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .nonHTTPResponse: return "Response was not HTTP"
            case .httpStatus(let code, _): return "HTTP \(code)"
            case .transport(let error): return error.localizedDescription
            }
        }
    }

    /// - Parameter retryCount: additional attempts after the first (0 = no retry).
    func data(
        for request: URLRequest,
        allowNon2xx: Bool = false,
        retryCount: Int = 0
    ) async throws -> Response {
        let redacted = request.url.map { LogRedaction.redactURL($0) } ?? "<nil>"
        var attempt = 0
        var lastError: Error?

        while attempt <= retryCount {
            try Task.checkCancellation()

            if attempt > 0 {
                let delayMs = UInt64(200 * attempt)
                logger.network.debug("Retry \(attempt)/\(retryCount) \(redacted)")
                try await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            attempt += 1

            do {
                logger.network.debug("→ \(request.httpMethod ?? "GET") \(redacted)")
                // session.data(for:) is cancelled when the parent Task is cancelled.
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()

                guard let http = response as? HTTPURLResponse else {
                    throw HTTPClientError.nonHTTPResponse
                }

                logger.network.debug("← \(http.statusCode) \(redacted)")

                if [502, 503, 504].contains(http.statusCode), attempt <= retryCount {
                    lastError = HTTPClientError.httpStatus(http.statusCode, data)
                    continue
                }

                if !allowNon2xx, !(200...299).contains(http.statusCode) {
                    throw HTTPClientError.httpStatus(http.statusCode, data)
                }

                return Response(data: data, httpResponse: http, statusCode: http.statusCode)
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as HTTPClientError {
                if case .httpStatus = error { throw error }
                lastError = error
                if attempt > retryCount { throw error }
            } catch {
                logger.network.error("Transport error: \(error.localizedDescription)")
                lastError = HTTPClientError.transport(error)
                if attempt > retryCount {
                    throw HTTPClientError.transport(error)
                }
            }
        }

        throw lastError ?? HTTPClientError.transport(URLError(.cannotConnectToHost))
    }

    func data(from url: URL, headers: [String: String] = [:]) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return try await data(for: request)
    }
}
