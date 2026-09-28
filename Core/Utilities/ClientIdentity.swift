import Foundation

/// Stable client identification used in X-Plex-* headers.
/// `clientIdentifier` is persisted in Keychain for the lifetime of the install.
struct ClientIdentity: Sendable {
    let clientIdentifier: String
    let product: String
    let version: String
    let platform: String
    let platformVersion: String
    let device: String
    let deviceName: String
    let deviceVendor: String

    static let productName = "Plex iOS Native"
    static let deviceVendorName = "Apple"

    /// Builds identity, creating and storing a new UUID if none exists.
    @MainActor
    static func resolve(keychain: KeychainStore) -> ClientIdentity {
        let id: String
        if let existing = try? keychain.get(KeychainStore.Keys.plexClientIdentifier),
           !existing.isEmpty {
            id = existing
        } else {
            id = UUID().uuidString.lowercased()
            try? keychain.set(id, forKey: KeychainStore.Keys.plexClientIdentifier)
        }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        #if os(iOS)
        let deviceModel = UIDevice.current.model
        let deviceName = UIDevice.current.name
        #else
        let deviceModel = "Unknown"
        let deviceName = "Unknown"
        #endif

        return ClientIdentity(
            clientIdentifier: id,
            product: productName,
            version: version,
            platform: "iOS",
            platformVersion: osVersion,
            device: deviceModel,
            deviceName: deviceName,
            deviceVendor: deviceVendorName
        )
    }

    /// Headers suitable for any plex.tv / PMS request.
    var plexHeaders: [String: String] {
        [
            "X-Plex-Client-Identifier": clientIdentifier,
            "X-Plex-Product": product,
            "X-Plex-Version": version,
            "X-Plex-Platform": platform,
            "X-Plex-Platform-Version": platformVersion,
            "X-Plex-Device": device,
            "X-Plex-Device-Name": deviceName,
            "X-Plex-Device-Vendor": deviceVendor,
            "Accept": "application/json"
        ]
    }
}

#if canImport(UIKit)
import UIKit
#endif
