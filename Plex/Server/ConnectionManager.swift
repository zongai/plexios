import Foundation
import Observation

/// Discovers servers, ranks connection candidates, maintains active connection.
@Observable
@MainActor
final class ConnectionManager {
    private(set) var servers: [PlexServer] = []
    private(set) var activeServer: PlexServer?
    private(set) var isRefreshing = false
    private(set) var lastError: PlexError?

    private let api: any PlexAPIProtocol
    private let networkMonitor: NetworkPathMonitor
    private let logger: LogRouter

    private var pathObservationTask: Task<Void, Never>?

    init(api: any PlexAPIProtocol, networkMonitor: NetworkPathMonitor, logger: LogRouter) {
        self.api = api
        self.networkMonitor = networkMonitor
        self.logger = logger
    }

    // MARK: - Discovery

    func discover(authToken: String) async {
        isRefreshing = true
        lastError = nil
        defer { isRefreshing = false }

        do {
            var discovered = try await api.fetchServers(authToken: authToken)
            // Probe & rank connections for each server
            discovered = await rankAll(discovered)
            servers = discovered

            // Keep active server if still present; otherwise pick first owned or first
            if let active = activeServer,
               let updated = discovered.first(where: { $0.machineIdentifier == active.machineIdentifier }) {
                activeServer = updated
            } else if activeServer == nil {
                activeServer = discovered.first(where: \.owned) ?? discovered.first
            }

            logger.plex.info("Discovered \(discovered.count) server(s)")
        } catch let error as PlexError {
            lastError = error
            if case .authentication(.tokenInvalid) = error {
                // Caller should sign out
            }
            logger.plex.error("Discovery failed: \(error.localizedDescription)")
        } catch {
            lastError = .network(.transport(error.localizedDescription))
        }
    }

    func selectServer(_ server: PlexServer) {
        activeServer = server
        logger.plex.info("Selected server \(server.name)")
    }

    /// Clear discovered state (e.g. on sign-out).
    func reset() {
        servers = []
        activeServer = nil
        lastError = nil
        stopObservingNetworkChanges()
    }

    /// Best base URL for the active server, if any.
    var activeBaseURL: URL? {
        activeServer?.preferredConnection?.baseURL
    }

    var activeToken: String? {
        activeServer?.accessToken
    }

    // MARK: - Ranking

    private func rankAll(_ servers: [PlexServer]) async -> [PlexServer] {
        await withTaskGroup(of: PlexServer.self) { group in
            for server in servers {
                group.addTask { await self.rankConnections(for: server) }
            }
            var result: [PlexServer] = []
            for await ranked in group {
                result.append(ranked)
            }
            return result
        }
    }

    private func rankConnections(for server: PlexServer) async -> PlexServer {
        var connections = server.connections

        // Probe in parallel with short timeout
        await withTaskGroup(of: (Int, Double?).self) { group in
            for (index, conn) in connections.enumerated() {
                group.addTask {
                    let latency = await self.probe(connection: conn, token: server.accessToken)
                    return (index, latency)
                }
            }
            for await (index, latency) in group {
                if let latency {
                    connections[index].latencyMs = latency
                    connections[index].lastSuccess = Date()
                }
            }
        }

        // Prefer probed successes, then rank score, then latency
        let reachable = connections.filter { $0.latencyMs != nil }
        let pool = reachable.isEmpty ? connections : reachable
        let sorted = pool.sorted {
            if $0.rankScore != $1.rankScore { return $0.rankScore < $1.rankScore }
            return ($0.latencyMs ?? .greatestFiniteMagnitude) < ($1.latencyMs ?? .greatestFiniteMagnitude)
        }

        var updated = server
        updated.connections = connections
        updated.preferredConnection = sorted.first
        return updated
    }

    private func probe(connection: PlexConnection, token: String) async -> Double? {
        guard let base = connection.baseURL else { return nil }
        let start = ContinuousClock.now
        do {
            _ = try await api.probeIdentity(baseURL: base, token: token)
            let elapsed = start.duration(to: .now)
            return Double(elapsed.components.seconds) * 1000
                + Double(elapsed.components.attoseconds) / 1e15 * 1000
        } catch {
            return nil
        }
    }

    // MARK: - Network path reactivity

    func startObservingNetworkChanges(authTokenProvider: @escaping () -> String?) {
        pathObservationTask?.cancel()
        pathObservationTask = Task { [weak self] in
            var previousSatisfied = true
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }

                let satisfied = self.networkMonitor.isSatisfied
                // Re-rank when connectivity is restored
                if satisfied && !previousSatisfied {
                    if let token = authTokenProvider() {
                        await self.discover(authToken: token)
                    }
                }
                previousSatisfied = satisfied
            }
        }
    }

    func stopObservingNetworkChanges() {
        pathObservationTask?.cancel()
        pathObservationTask = nil
    }
}
