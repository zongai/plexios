import SwiftUI

struct SettingsTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs = PlaybackSettingsStore.shared.preferences

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

                Section("Playback") {
                    Picker("Default speed", selection: $prefs.defaultPlaybackRate) {
                        ForEach(PlaybackPreferences.rateOptions, id: \.self) { rate in
                            Text(rate == 1.0 ? "1x (Normal)" : String(format: "%.2gx", rate))
                                .tag(rate)
                        }
                    }
                    .onChange(of: prefs.defaultPlaybackRate) { _, _ in savePrefs() }

                    Picker("Default aspect", selection: $prefs.defaultAspectMode) {
                        ForEach(VideoAspectMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .onChange(of: prefs.defaultAspectMode) { _, _ in savePrefs() }

                    Toggle("Subtitles on by default", isOn: $prefs.subtitlesEnabled)
                        .onChange(of: prefs.subtitlesEnabled) { _, _ in savePrefs() }

                    Toggle("Autoplay next episode", isOn: $prefs.autoPlayNextEpisode)
                        .onChange(of: prefs.autoPlayNextEpisode) { _, _ in savePrefs() }

                    Picker("Max quality", selection: Binding(
                        get: { prefs.maxVideoBitrateKbps ?? 0 },
                        set: { newValue in
                            prefs.maxVideoBitrateKbps = newValue == 0 ? nil : newValue
                            savePrefs()
                        }
                    )) {
                        Text("Original").tag(0)
                        Text("20 Mbps").tag(20_000)
                        Text("12 Mbps").tag(12_000)
                        Text("8 Mbps").tag(8_000)
                        Text("4 Mbps").tag(4_000)
                        Text("2 Mbps").tag(2_000)
                    }
                }

                Section("Codecs (device)") {
                    let caps = IOSCapabilities.current
                    LabeledContent("HEVC / H.265", value: caps.supportsHEVC ? "Supported" : "No")
                    LabeledContent("VP9", value: caps.supportsVP9 ? "Supported" : "No")
                    LabeledContent("AV1", value: caps.supportsAV1 ? "Supported" : "No")
                    Text("Unsupported codecs are remuxed or transcoded by the server.")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.secondaryText)
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
            .onAppear {
                prefs = PlaybackSettingsStore.shared.preferences
            }
        }
    }

    private func savePrefs() {
        PlaybackSettingsStore.shared.preferences = prefs
    }
}
