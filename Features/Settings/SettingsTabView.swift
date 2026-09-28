import SwiftUI

struct SettingsTabView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            List {
                Section("Account") {
                    if case .signedIn = environment.authenticationService.state {
                        LabeledContent("Status", value: "Signed in")
                    }
                    Button("Sign Out", role: .destructive) {
                        Task {
                            await environment.authenticationService.signOut()
                            environment.connectionManager.reset()
                        }
                    }
                }

                Section("Server") {
                    if environment.connectionManager.servers.isEmpty {
                        Text("No servers discovered")
                            .foregroundStyle(AppColors.secondaryText)
                    } else {
                        ForEach(environment.connectionManager.servers) { server in
                            Button {
                                environment.connectionManager.selectServer(server)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(server.name)
                                        if let conn = server.preferredConnection {
                                            Text(conn.uri)
                                                .font(AppTypography.caption)
                                                .foregroundStyle(AppColors.secondaryText)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if environment.connectionManager.activeServer?.machineIdentifier == server.machineIdentifier {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(AppColors.accent)
                                    }
                                }
                            }
                        }
                    }

                    Button("Refresh servers") {
                        Task {
                            if let token = environment.authenticationService.authToken {
                                await environment.connectionManager.discover(authToken: token)
                            }
                        }
                    }
                }

                Section("Network") {
                    LabeledContent("Path", value: environment.networkMonitor.currentPathDescription)
                }

                Section("Cache") {
                    Button("Clear response & image cache", role: .destructive) {
                        Task {
                            if let mid = environment.serverContext?.machineIdentifier {
                                await environment.libraryRepository.invalidate(machineIdentifier: mid)
                                await environment.hubRepository.invalidate(machineIdentifier: mid)
                            }
                            await ImagePipeline.shared.clearAll()
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App", value: "PlexiOS")
                    LabeledContent("Version", value: "0.1.0")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
