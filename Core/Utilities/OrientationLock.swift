import UIKit

/// Controls preferred interface orientation while the video player is open.
/// Requires `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` to read `mask`.
@MainActor
enum OrientationLock {
    /// Current mask returned to UIKit. Defaults to phone: all but upside-down.
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    /// Lock to landscape and request a geometry update so playback opens sideways.
    static func lockLandscape() {
        mask = .landscape
        requestGeometry(mask)
    }

    /// Restore normal app orientations (portrait + landscape).
    static func unlockAll() {
        mask = .allButUpsideDown
        // Prefer returning to portrait when leaving the player on phone.
        requestGeometry(.portrait)
    }

    private static func requestGeometry(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }

        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        scene.requestGeometryUpdate(prefs) { _ in
            // Ignore geometry errors (e.g. iPad multitasking constraints).
        }

        // Nudge root controllers to re-query supported orientations.
        scene.windows.forEach { window in
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
