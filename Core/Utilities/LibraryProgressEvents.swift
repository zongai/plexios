import Foundation

/// Posted when watch state / favorites change so Home can refresh Continue Watching.
enum LibraryProgressEvents {
    static let didChange = Notification.Name("plex.libraryProgressDidChange")
    /// Pop the active tab's NavigationPath to root (e.g. re-tap tab).
    static let popToRoot = Notification.Name("plex.navigation.popToRoot")

    static func postProgressDidChange(machineIdentifier: String? = nil) {
        var info: [AnyHashable: Any] = [:]
        if let machineIdentifier {
            info["machineIdentifier"] = machineIdentifier
        }
        NotificationCenter.default.post(name: didChange, object: nil, userInfo: info)
    }

    static func postPopToRoot() {
        NotificationCenter.default.post(name: popToRoot, object: nil)
    }
}
