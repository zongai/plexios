import Foundation
import SwiftData

/// SwiftData container. Schema is intentionally minimal until offline
/// persistence models are introduced; empty schema must not crash launch.
@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer?

    init(inMemory: Bool = false) {
        // No SwiftData models registered yet — repositories use ResponseCache.
        // Keep optional container so app launches without fatalError.
        container = nil
    }
}
