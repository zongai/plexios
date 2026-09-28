import Foundation
import Network
import Observation

/// Observes network path changes via Network.framework.
/// ConnectionManager (Phase 2) will react to updates.
@Observable
@MainActor
final class NetworkPathMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.plexios.networkpath")

    private(set) var isSatisfied: Bool = true
    private(set) var isExpensive: Bool = false
    private(set) var isConstrained: Bool = false
    private(set) var usesWiFi: Bool = false
    private(set) var usesCellular: Bool = false
    private(set) var usesWired: Bool = false

    var currentPathDescription: String {
        guard isSatisfied else { return "Offline" }
        var parts: [String] = []
        if usesWiFi { parts.append("Wi-Fi") }
        if usesCellular { parts.append("Cellular") }
        if usesWired { parts.append("Wired") }
        if parts.isEmpty { parts.append("Other") }
        if isExpensive { parts.append("expensive") }
        if isConstrained { parts.append("constrained") }
        return parts.joined(separator: " · ")
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.apply(path)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    private func apply(_ path: NWPath) {
        isSatisfied = path.status == .satisfied
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained
        usesWiFi = path.usesInterfaceType(.wifi)
        usesCellular = path.usesInterfaceType(.cellular)
        usesWired = path.usesInterfaceType(.wiredEthernet)
    }
}
