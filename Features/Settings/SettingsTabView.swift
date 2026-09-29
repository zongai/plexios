import SwiftUI

struct SettingsTabView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var prefs = PlaybackSettingsStore.shared.preferences
    @State private var homePrefs = HomeSettingsStore.shared.preferences
    @State private var homeLibraries: [PlexLibrary] = []

    var body: some View {
        NavigationStack {
            List {
                accountSection
                serverSection
                homeSection
                iptvSettingsSection
                playbackSection
                playerEngineSection
                codecsSection
                networkSection
                cacheSection
                aboutSection
            }
            .navigationTitle(L10n.settings)
            .scrollContentBackground(.hidden)
            .background(PlexColors.background)
            .onAppear {
                prefs = PlaybackSettingsStore.shared.preferences
                homePrefs = HomeSettingsStore.shared.preferences
            }
            .task {
                if let context = environment.serverContext {
                    homeLibraries = (try? await environment.libraryRepository.libraries(context: context)) ?? []
                }
            }
        }
    }

    // MARK: - Sections

    private var accountSection: some View {
        Section(String(localized: "settings.account")) {
            if case .signedIn = environment.authenticationService.state {
                LabeledContent(String(localized: "settings.status"), value: String(localized: "settings.signed_in"))
            }
            Button(String(localized: "settings.sign_out"), role: .destructive) {
                Task {
                    await environment.authenticationService.signOut()
                    environment.connectionManager.reset()
                }
            }
        }
    }

    private var serverSection: some View {
        Section(String(localized: "settings.server")) {
            if environment.connectionManager.servers.isEmpty {
                Text(String(localized: "settings.no_servers"))
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

            Button(String(localized: "settings.refresh_servers")) {
                Task {
                    if let token = environment.authenticationService.authToken {
                        await environment.connectionManager.discover(authToken: token)
                    }
                }
            }
        }
    }

    private var iptvSettingsSection: some View {
        Section(String(localized: "iptv.title")) {
            NavigationLink {
                IPTVSettingsView()
            } label: {
                Label(String(localized: "iptv.playlists"), systemImage: "tv")
            }
        }
    }

    private var homeSection: some View {
        Section {
            Toggle(String(localized: "home.pref.continue"), isOn: Binding(
                get: { homePrefs.showContinueWatching },
                set: {
                    homePrefs.showContinueWatching = $0
                    HomeSettingsStore.shared.preferences = homePrefs
                }
            ))
            Toggle(String(localized: "home.pref.recently_played"), isOn: Binding(
                get: { homePrefs.showRecentlyPlayed },
                set: {
                    homePrefs.showRecentlyPlayed = $0
                    HomeSettingsStore.shared.preferences = homePrefs
                }
            ))

            if homeLibraries.isEmpty {
                Text(String(localized: "home.pref.no_libraries"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(homeLibraries) { lib in
                    Toggle(lib.title, isOn: Binding(
                        get: { homePrefs.isLibraryEnabled(lib.key) },
                        set: { enabled in
                            homePrefs.setLibrary(lib.key, enabled: enabled)
                            HomeSettingsStore.shared.preferences = homePrefs
                        }
                    ))
                }
            }

            Picker(String(localized: "home.pref.max_items"), selection: Binding(
                get: { homePrefs.maxItemsPerHub },
                set: {
                    homePrefs.maxItemsPerHub = $0
                    HomeSettingsStore.shared.preferences = homePrefs
                }
            )) {
                Text("10").tag(10)
                Text("15").tag(15)
                Text("20").tag(20)
                Text("30").tag(30)
                Text("50").tag(50)
            }
        } header: {
            Text(String(localized: "home.pref.section"))
        } footer: {
            Text(String(localized: "home.pref.footer_libraries"))
        }
    }

    private var playbackSection: some View {
        Section(L10n.settingsPlayback) {
            Picker(String(localized: "settings.default_speed"), selection: $prefs.defaultPlaybackRate) {
                ForEach(PlaybackPreferences.rateOptions, id: \.self) { rate in
                    Text(rate == 1.0 ? String(localized: "settings.speed_normal") : String(format: "%.2gx", rate))
                        .tag(rate)
                }
            }
            .onChange(of: prefs.defaultPlaybackRate) { _, _ in savePrefs() }

            Picker(String(localized: "settings.default_aspect"), selection: $prefs.defaultAspectMode) {
                ForEach(VideoAspectMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: prefs.defaultAspectMode) { _, _ in savePrefs() }

            Toggle(String(localized: "settings.subtitles_default"), isOn: $prefs.subtitlesEnabled)
                .onChange(of: prefs.subtitlesEnabled) { _, _ in savePrefs() }

            ForEach(0..<3, id: \.self) { index in
                Picker(String(format: String(localized: "settings.audio_priority"), index + 1), selection: audioLangBinding(at: index)) {
                    ForEach(PlaybackPreferences.languageOptions, id: \.code) { opt in
                        Text(String(localized: String.LocalizationValue(opt.labelKey))).tag(opt.code)
                    }
                }
            }

            ForEach(0..<3, id: \.self) { index in
                Picker(String(format: String(localized: "settings.subtitle_priority"), index + 1), selection: subtitleLangBinding(at: index)) {
                    ForEach(PlaybackPreferences.languageOptions, id: \.code) { opt in
                        Text(String(localized: String.LocalizationValue(opt.labelKey))).tag(opt.code)
                    }
                }
                .disabled(!prefs.subtitlesEnabled)
            }

            Toggle(String(localized: "settings.native_engine"), isOn: $prefs.allowNativeMediaEngine)
                .onChange(of: prefs.allowNativeMediaEngine) { _, _ in savePrefs() }

            Text(nativeEngineHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)

            if prefs.allowNativeMediaEngine {
                nativeCapabilitiesNote
            }

            Toggle(String(localized: "settings.autoplay_next"), isOn: $prefs.autoPlayNextEpisode)
                .onChange(of: prefs.autoPlayNextEpisode) { _, _ in savePrefs() }

            Picker(String(localized: "settings.max_quality"), selection: maxQualityBinding) {
                Text(String(localized: "settings.quality_original")).tag(0)
                Text(String(localized: "settings.quality_20mbps")).tag(20_000)
                Text(String(localized: "settings.quality_12mbps")).tag(12_000)
                Text(String(localized: "settings.quality_8mbps")).tag(8_000)
                Text(String(localized: "settings.quality_4mbps")).tag(4_000)
                Text(String(localized: "settings.quality_2mbps")).tag(2_000)
            }
        }
    }

    private var playerEngineSection: some View {
        Section(String(localized: "settings.player_engine")) {
            Toggle(String(localized: "settings.allow_vlc"), isOn: $prefs.allowVLCPlayer)
                .onChange(of: prefs.allowVLCPlayer) { _, _ in savePrefs() }
            Toggle(String(localized: "settings.prefer_system_player"), isOn: $prefs.preferSystemPlayer)
                .onChange(of: prefs.preferSystemPlayer) { _, _ in savePrefs() }
            Text(vlcHelpText)
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private var codecsSection: some View {
        Section(String(localized: "settings.codecs")) {
            let caps = IOSCapabilities.current
            LabeledContent("HEVC / H.265", value: caps.supportsHEVC ? String(localized: "settings.codec_hw") : String(localized: "settings.codec_transcode"))
            LabeledContent("VP9", value: (prefs.allowVLCPlayer && !prefs.preferSystemPlayer) ? String(localized: "settings.codec_vlc_dp") : String(localized: "settings.codec_server_tc"))
            LabeledContent("AV1", value: caps.supportsAV1 ? String(localized: "settings.codec_hw") : String(localized: "settings.codec_transcode"))
            LabeledContent(String(localized: "settings.codec_opus"), value: (prefs.allowVLCPlayer && !prefs.preferSystemPlayer) ? String(localized: "settings.codec_vlc_dp") : String(localized: "settings.codec_server_aac"))
            Text(String(localized: "settings.codecs_footer"))
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.secondaryText)
        }
    }

    private var networkSection: some View {
        Section(String(localized: "settings.network")) {
            LabeledContent(String(localized: "settings.network_path"), value: environment.networkMonitor.currentPathDescription)
        }
    }

    private var cacheSection: some View {
        Section(L10n.settingsCache) {
            Button(L10n.clearCache, role: .destructive) {
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
            LabeledContent(String(localized: "settings.app_name"), value: "PlexiOS")
            LabeledContent(L10n.version, value: "0.1.0")
        }
    }

    private var vlcHelpText: String {
        if VLCPlaybackBackend.isLinked {
            return String(localized: "settings.vlc_help_linked")
        }
        return String(localized: "settings.vlc_help_missing")
    }

    private var nativeEngineHelpText: String {
        if FFmpegAvailability.isLinked {
            return String(localized: "settings.native_help_linked")
        }
        return String(localized: "settings.native_help_missing")
    }

    private var nativeCapabilitiesNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "settings.native_caps_title"))
                .font(.subheadline.weight(.semibold))
            Text(String(localized: "settings.native_caps_np"))
                .font(.caption)
            Text(String(localized: "settings.native_caps_audio"))
                .font(.caption)
            Text(String(localized: "settings.native_caps_pip"))
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

    private func audioLangBinding(at index: Int) -> Binding<String> {
        languageListBinding(index: index, get: { prefs.preferredAudioLanguages }, set: { prefs.preferredAudioLanguages = $0 })
    }

    private func subtitleLangBinding(at index: Int) -> Binding<String> {
        languageListBinding(index: index, get: { prefs.preferredSubtitleLanguages }, set: { prefs.preferredSubtitleLanguages = $0 })
    }

    private func languageListBinding(index: Int, get: @escaping () -> [String], set: @escaping ([String]) -> Void) -> Binding<String> {
        Binding(
            get: {
                let list = get()
                return index < list.count ? list[index] : ""
            },
            set: { newValue in
                var list = get()
                while list.count <= index { list.append("") }
                list[index] = newValue
                var ordered: [String] = []
                for i in 0..<max(list.count, index + 1) {
                    let v = i < list.count ? list[i] : ""
                    if !v.isEmpty { ordered.append(v) }
                }
                var seen = Set<String>()
                set(ordered.filter { seen.insert($0).inserted })
                savePrefs()
            }
        )
    }

    private func savePrefs() {
        PlaybackSettingsStore.shared.preferences = prefs
    }
}
