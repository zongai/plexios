import SwiftUI
import UIKit

@main
struct PlexApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var environment = AppEnvironment()

    init() {
        // Ensure file log + crash hooks are active before any UI / playback work.
        _ = FileLogStore.shared
        FileLogStore.shared.append(level: .info, category: "app", message: "PlexApp init")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .tint(PlexColors.accent)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)) { _ in
                    FileLogStore.shared.appendAndFlush(level: .info, category: "app", message: "willTerminate")
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    FileLogStore.shared.appendAndFlush(level: .info, category: "app", message: "didEnterBackground")
                    FileLogStore.shared.flush()
                }
        }
    }
}
