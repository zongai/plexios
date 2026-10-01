import UIKit

/// App chrome stays portrait-only. Landscape is allowed only while a video player is open.
/// Requires `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` to read `mask`.
@MainActor
enum OrientationLock {
    /// Default: portrait app UI. Player calls `lockLandscape()` while presented.
    static var mask: UIInterfaceOrientationMask = .portrait

    private static var unlockTask: Task<Void, Never>?

    /// Enter player / IPTV fullscreen: allow landscape and request sideways geometry.
    static func lockLandscape() {
        unlockTask?.cancel()
        unlockTask = nil
        mask = .landscape
        requestGeometry(.landscape)
    }

    /// Leave player: return to portrait and **keep** portrait (do not re-enable free rotation).
    static func unlockAll() {
        unlockTask?.cancel()
        unlockTask = nil
        mask = .portrait
        requestGeometry(.portrait)
    }

    private static func requestGeometry(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = activeWindowScene() else {
            notifyOrientationChange()
            return
        }

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
