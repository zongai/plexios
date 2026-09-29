import SwiftUI

struct SettingsTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs = PlaybackSettingsStore.shared.preferences

    var body: some View {
        NavigationStack {
            List {
                accountSection
                serverSection
                playbackSection
                playerEngineSection
                codecsSection
                networkSection
                cacheSection
                aboutSection
            }
            .navigationTitle("Settings")
            .onAppear {
                prefs = PlaybackSettingsStore.shared.preferences
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
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
    }

    private var serverSection: some View {
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
    }

    private var playbackSection: some View {
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

            Toggle("Native Media Engine (experimental)", isOn: $prefs.allowNativeMediaEngine)
                .onChange(of: prefs.allowNativeMediaEngine) { _, _ in savePrefs() }

            Text(nativeEngineHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if prefs.allowNativeMediaEngine {
                nativeCapabilitiesNote
            }

            Toggle("Autoplay next episode", isOn: $prefs.autoPlayNextEpisode)
                .onChange(of: prefs.autoPlayNextEpisode) { _, _ in savePrefs() }

            Picker("Max quality", selection: maxQualityBinding) {
                Text("Original").tag(0)
                Text("20 Mbps").tag(20_000)
                Text("12 Mbps").tag(12_000)
                Text("8 Mbps").tag(8_000)
                Text("4 Mbps").tag(4_000)
                Text("2 Mbps").tag(2_000)
            }
        }
    }

    private var playerEngineSection: some View {
        Section("Player engine") {
            Toggle("MobileVLCKit Direct Play", isOn: $prefs.allowVLCPlayer)
                .onChange(of: prefs.allowVLCPlayer) { _, _ in savePrefs() }
            Toggle("Prefer system player (AVPlayer)", isOn: $prefs.preferSystemPlayer)
                .onChange(of: prefs.preferSystemPlayer) { _, _ in savePrefs() }
            Text(vlcHelpText)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private var codecsSection: some View {
        Section("Codecs (device)") {
            let caps = IOSCapabilities.current
            LabeledContent("HEVC / H.265", value: caps.supportsHEVC ? "Hardware" : "Transcode")
            LabeledContent("VP9", value: (prefs.allowVLCPlayer && !prefs.preferSystemPlayer) ? "VLC Direct Play" : "Server transcode")
            LabeledContent("AV1", value: caps.supportsAV1 ? "Hardware" : "Transcode")
            LabeledContent("OPUS audio", value: (prefs.allowVLCPlayer && !prefs.preferSystemPlayer) ? "VLC Direct Play" : "Server transcode → AAC")
            Text("With MobileVLCKit enabled, MKV/VP9/OPUS and advanced subtitles can Direct Play. Prefer system player for PiP / AirPlay Video.")
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private var networkSection: some View {
        Section("Network") {
            LabeledContent("Path", value: environment.networkMonitor.currentPathDescription)
        }
    }

    private var cacheSection: some View {
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
    }

    private var aboutSection: some View {
        Section(L10n.settingsAbout) {
            Text(L10n.languageNote)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
            LabeledContent("App", value: "PlexiOS")
            LabeledContent("Version", value: "0.1.0")
        }
    }

    private var vlcHelpText: String {
        if VLCPlaybackBackend.isLinked {
            return "VLC is linked. Direct Play uses MobileVLCKit unless you prefer the system player. PiP and AirPlay Video are limited on the VLC path."
        }
        return "MobileVLCKit is not linked in this build (SPM package missing). Playback stays on AVPlayer until the package resolves."
    }

    private var nativeEngineHelpText: String {
        if FFmpegAvailability.isLinked {
            return "FFmpeg linked. Direct Play may use the native pipeline; failures fall back to AVPlayer / Transcode."
        }
        return "FFmpeg is not linked in this build. Toggle is kept for UI, but playback stays on AVPlayer until you add XCFrameworks (docs/ffmpeg-integration.md)."
    }

    private var nativeCapabilitiesNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Native system capabilities")
                .font(.subheadline.weight(.semibold))
            Text("Now Playing / Lock Screen / Remote: Yes")
                .font(.caption)
            Text("Background Audio / AirPlay Audio: Yes")
                .font(.caption)
            Text("PiP / AirPlay Video: No on Metal path (use AVPlayer)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    private var maxQualityBinding: Binding<Int> {
        Binding(
            get: { prefs.maxVideoBitrateKbps ?? 0 },
            set: { newValue in
                prefs.maxVideoBitrateKbps = newValue == 0 ? nil : newValue
                savePrefs()
            }
        )
    }

    private func savePrefs() {
        PlaybackSettingsStore.shared.preferences = prefs
    }
}
