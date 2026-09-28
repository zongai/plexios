import Foundation

/// Posts playback progress to PMS `/:/timeline`.
actor TimelineReporter {
    private let http: HTTPClient
    private let logger: LogRouter

    init(http: HTTPClient, logger: LogRouter) {
        self.http = http
        self.logger = logger
    }

    func report(
        baseURL: URL,
        token: String,
        clientIdentifier: String,
        session: PlaybackSession,
        continuing: Bool = false
    ) async {
        let state = await session.plexStateString
        let time = await session.positionMs
        let duration = await session.durationMs
        let ratingKey = await session.ratingKey
        let key = await session.metadataKey

        var components = URLComponents(
            url: baseURL.appendingPathComponent(":/timeline"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "time", value: "\(time)"),
            URLQueryItem(name: "duration", value: "\(duration)"),
            URLQueryItem(name: "continuing", value: continuing ? "1" : "0"),
            URLQueryItem(name: "X-Plex-Token", value: token),
            URLQueryItem(name: "X-Plex-Client-Identifier", value: clientIdentifier)
        ]

        guard let url = components?.url else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            _ = try await http.data(for: request, allowNon2xx: true)
            await session.markReported()
            logger.playback.debug("Timeline \(state) t=\(time)")
        } catch {
            logger.playback.error("Timeline report failed: \(error.localizedDescription)")
        }
    }

    func scrobble(baseURL: URL, token: String, key: String) async {
        await scrobbleRequest(baseURL: baseURL, token: token, key: key, path: ":/scrobble")
    }

    func unscrobble(baseURL: URL, token: String, key: String) async {
        await scrobbleRequest(baseURL: baseURL, token: token, key: key, path: ":/unscrobble")
    }

    private func scrobbleRequest(baseURL: URL, token: String, key: String, path: String) async {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "key", value: key),
            URLQueryItem(name: "identifier", value: "com.plexapp.plugins.library"),
            URLQueryItem(name: "X-Plex-Token", value: token)
        ]
        guard let url = components?.url else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
        do {
            _ = try await http.data(for: request, allowNon2xx: true)
        } catch {
            logger.playback.error("Scrobble failed: \(error.localizedDescription)")
        }
    }
}
