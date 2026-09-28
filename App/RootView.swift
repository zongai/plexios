import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var didBootstrap = false

    var body: some View {
        Group {
            switch environment.authenticationService.state {
            case .unknown:
                ProgressView("Starting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.background)
                    .accessibilityLabel("Starting")
            case .signedOut, .signingIn:
                SignInView()
            case .signedIn:
                AdaptiveRootView()
            }
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await environment.bootstrap()
        }
        .onChange(of: environment.authenticationService.state) { _, newState in
            if case .signedIn = newState {
                Task {
                    if let token = environment.authenticationService.authToken {
                        await environment.connectionManager.discover(authToken: token)
                        environment.connectionManager.startObservingNetworkChanges {
                            environment.authenticationService.authToken
                        }
                    }
                }
            }
        }
    }
}

#Preview("iPhone") {
    RootView()
        .environment(AppEnvironment())
}

#Preview("iPad", traits: .fixedLayout(width: 1024, height: 768)) {
    RootView()
        .environment(AppEnvironment())
}
