import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var didBootstrap = false
    @State private var bootstrapFinished = false

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
                signedInRoot
            }
        }
        .task {
            guard !didBootstrap else { return }
            didBootstrap = true
            await environment.bootstrap()
            bootstrapFinished = true
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

    @ViewBuilder
    private var signedInRoot: some View {
        let connection = environment.connectionManager
        // Wait until discovery finished and we have a usable base URL.
        // Otherwise Home loads with nil/bad context → brief "Something went wrong".
        if connection.activeServer?.preferredConnection?.baseURL != nil {
            AdaptiveRootView()
        } else if !bootstrapFinished || connection.isRefreshing {
            ProgressView("Connecting to server…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.background)
                .accessibilityLabel("Connecting to server")
        } else if let error = connection.lastError {
            ErrorStateView(message: error.localizedDescription) {
                Task {
                    if let token = environment.authenticationService.authToken {
                        await connection.discover(authToken: token)
                    }
                }
            }
        } else if connection.servers.isEmpty {
            EmptyStateView(
                title: "No servers found",
                systemImage: "server.rack",
                subtitle: "Sign in on plex.tv and make sure your Plex Media Server is online.",
                actionTitle: "Refresh",
                action: {
                    Task {
                        if let token = environment.authenticationService.authToken {
                            await connection.discover(authToken: token)
                        }
                    }
                }
            )
        } else {
            // Servers listed but none reachable yet
            ProgressView("Finding a working connection…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppColors.background)
                .task {
                    // One more discovery pass in case probes raced
                    if let token = environment.authenticationService.authToken {
                        await connection.discover(authToken: token)
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
