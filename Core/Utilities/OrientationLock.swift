import UIKit

/// Controls preferred interface orientation while the video player is open.
/// Requires `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` to read `mask`.
@MainActor
enum OrientationLock {
    /// Current mask returned to UIKit. Defaults to phone: all but upside-down.
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown

    private static var unlockTask: Task<Void, Never>?

    /// Lock to landscape and request a geometry update so playback opens sideways.
    static func lockLandscape() {
        unlockTask?.cancel()
        unlockTask = nil
        mask = .landscape
        requestGeometry(.landscape)
    }

    /// Leave the player: force portrait, then restore free rotation shortly after.
    static func unlockAll() {
        unlockTask?.cancel()
        // Temporarily allow only portrait so the system must rotate back.
        mask = .portrait
        requestGeometry(.portrait)

        unlockTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // App UI may rotate freely again (except upside-down on phone).
            mask = .allButUpsideDown
            notifyOrientationChange()
        }
    }

    private static func requestGeometry(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = activeWindowScene() else { return }

        let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
        scene.requestGeometryUpdate(prefs) { _ in
            // Ignore geometry errors (e.g. iPad multitasking constraints).
        }
        notifyOrientationChange()
    }

    private static func notifyOrientationChange() {
        guard let scene = activeWindowScene() else { return }
        scene.windows.forEach { window in
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    private static func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    }
}
