import SwiftUI

/// Settings root: one primary list → secondary pages by function.
struct SettingsTabView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        NavigationStack {
            List {
                Section(String(localized: "settings.section_account")) {
                    NavigationLink {
                        AccountServerSettingsView()
                    } label: {
                        Label(String(localized: "settings.account_server"), systemImage: "person.crop.circle")
                    }
                }

                Section(String(localized: "settings.section_display")) {
                    NavigationLink {
                        HomeDisplaySettingsView()
                    } label: {
                        Label(String(localized: "home.pref.section"), systemImage: "rectangle.grid.1x2")
                    }
                }

                Section(String(localized: "settings.section_playback")) {
                    NavigationLink {
                        PlaybackSettingsDetailView()
                    } label: {
                        Label(L10n.settingsPlayback, systemImage: "play.circle")
                    }
                    NavigationLink {
                        PlayerEngineSettingsView()
                    } label: {
                        Label(String(localized: "settings.player_engine"), systemImage: "cpu")
                    }
                }

                Section(String(localized: "settings.section_media_sources")) {
                    NavigationLink {
                        IPTVSettingsView()
                    } label: {
                        Label(String(localized: "iptv.title"), systemImage: "tv")
                    }
                }

                Section(String(localized: "settings.section_storage")) {
                    NavigationLink {
                        CacheNetworkSettingsView()
                    } label: {
                        Label(String(localized: "settings.storage_network"), systemImage: "internaldrive")
                    }
                }

                Section(String(localized: "settings.section_diagnostics")) {
                    NavigationLink {
                        DiagnosticsLogView()
                    } label: {
                        Label(String(localized: "settings.logs"), systemImage: "doc.text.magnifyingglass")
                    }
                }

                Section(String(localized: "settings.section_about")) {
                    NavigationLink {
                        AboutSettingsView()
                    } label: {
                        Label(L10n.settingsAbout, systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(L10n.settings)
            .scrollContentBackground(.hidden)
            .background(PlexColors.background)
        }
    }
}

// MARK: - Account & Server

struct AccountServerSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
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
                                if environment.connectionManager.activeServer?.machineIdentifier
                                    == server.machineIdentifier {
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
        .navigationTitle(String(localized: "settings.account_server"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Home display

struct HomeDisplaySettingsView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var homePrefs = HomeSettingsStore.shared.preferences
    @State private var homeLibraries: [PlexLibrary] = []

    var body: some View {
        List {
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
            }

            Section(String(localized: "libraries.title")) {
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
            }

            Section {
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
            } footer: {
                Text(String(localized: "home.pref.footer_libraries"))
            }
        }
        .navigationTitle(String(localized: "home.pref.section"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { homePrefs = HomeSettingsStore.shared.preferences }
        .task {
            if let context = environment.serverContext {
                homeLibraries = (try? await environment.libraryRepository.libraries(context: context)) ?? []
            }
        }
    }
}

// MARK: - Playback

struct PlaybackSettingsDetailView: View {
    @State private var prefs = PlaybackSettingsStore.shared.preferences

    var body: some View {
        List {
            Section(String(localized: "settings.playback_defaults")) {
                Picker(String(localized: "settings.default_speed"), selection: $prefs.defaultPlaybackRate) {
                    ForEach(PlaybackPreferences.rateOptions, id: \.self) { rate in
                        Text(rate == 1.0 ? String(localized: "settings.speed_normal") : String(format: "%.2gx", rate))
                            .tag(rate)
                    }
                }
                .onChange(of: prefs.defaultPlaybackRate) { _, _ in save() }

                Picker(String(localized: "settings.default_aspect"), selection: $prefs.defaultAspectMode) {
                    ForEach(VideoAspectMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .onChange(of: prefs.defaultAspectMode) { _, _ in save() }

                Toggle(String(localized: "settings.autoplay_next"), isOn: $prefs.autoPlayNextEpisode)
                    .onChange(of: prefs.autoPlayNextEpisode) { _, _ in save() }

                Picker(String(localized: "settings.max_quality"), selection: maxQualityBinding) {
                    Text(String(localized: "settings.quality_original")).tag(0)
                    Text(String(localized: "settings.quality_20mbps")).tag(20_000)
                    Text(String(localized: "settings.quality_12mbps")).tag(12_000)
                    Text(String(localized: "settings.quality_8mbps")).tag(8_000)
                    Text(String(localized: "settings.quality_4mbps")).tag(4_000)
                    Text(String(localized: "settings.quality_2mbps")).tag(2_000)
                }
            }

            Section(String(localized: "settings.languages")) {
                Toggle(String(localized: "settings.subtitles_default"), isOn: $prefs.subtitlesEnabled)
                    .onChange(of: prefs.subtitlesEnabled) { _, _ in save() }

                NavigationLink {
                    LanguagePriorityListView(kind: .audio)
                } label: {
                    HStack {
                        Text(String(localized: "settings.audio_languages"))
                        Spacer()
                        Text(summary(prefs.preferredAudioLanguages))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                }

                NavigationLink {
                    LanguagePriorityListView(kind: .subtitle)
                } label: {
                    HStack {
                        Text(String(localized: "settings.subtitle_languages"))
                        Spacer()
                        Text(summary(prefs.preferredSubtitleLanguages))
                            .foregroundStyle(AppColors.secondaryText)
                            .lineLimit(1)
                    }
                }
                .disabled(!prefs.subtitlesEnabled)
            }
        }
        .navigationTitle(L10n.settingsPlayback)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefs = PlaybackSettingsStore.shared.preferences }
    }

    private var maxQualityBinding: Binding<Int> {
        Binding(
            get: { prefs.maxVideoBitrateKbps ?? 0 },
            set: { newValue in
                prefs.maxVideoBitrateKbps = newValue == 0 ? nil : newValue
                save()
            }
        )
    }

    private func summary(_ codes: [String]) -> String {
        if codes.isEmpty { return String(localized: "lang.auto") }
        let names = codes.prefix(3).map { code -> String in
            if let opt = PlaybackPreferences.languageOptions.first(where: { $0.code == code }) {
                return String(localized: String.LocalizationValue(opt.labelKey))
            }
            return code
        }
        let joined = names.joined(separator: " → ")
        return codes.count > 3 ? joined + "…" : joined
    }

    private func save() {
        PlaybackSettingsStore.shared.preferences = prefs
    }
}

// MARK: - Player engine

struct PlayerEngineSettingsView: View {
    @State private var prefs = PlaybackSettingsStore.shared.preferences

    var body: some View {
        List {
            Section {
                Toggle(String(localized: "settings.allow_vlc"), isOn: $prefs.allowVLCPlayer)
                    .onChange(of: prefs.allowVLCPlayer) { _, _ in save() }
                Toggle(String(localized: "settings.prefer_system_player"), isOn: $prefs.preferSystemPlayer)
                    .onChange(of: prefs.preferSystemPlayer) { _, _ in save() }
                Text(vlcHelpText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }

            Section {
                Toggle(String(localized: "settings.native_engine"), isOn: $prefs.allowNativeMediaEngine)
                    .onChange(of: prefs.allowNativeMediaEngine) { _, _ in save() }
                Text(nativeHelpText)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
            }

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
        .navigationTitle(String(localized: "settings.player_engine"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { prefs = PlaybackSettingsStore.shared.preferences }
    }

    private var vlcHelpText: String {
        VLCPlaybackBackend.isLinked
            ? String(localized: "settings.vlc_help_linked")
            : String(localized: "settings.vlc_help_missing")
    }

    private var nativeHelpText: String {
        FFmpegAvailability.isLinked
            ? String(localized: "settings.native_help_linked")
            : String(localized: "settings.native_help_missing")
    }

    private func save() {
        PlaybackSettingsStore.shared.preferences = prefs
    }
}

// MARK: - Cache & network

struct CacheNetworkSettingsView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        List {
            Section(String(localized: "settings.network")) {
                LabeledContent(
                    String(localized: "settings.network_path"),
                    value: environment.networkMonitor.currentPathDescription
                )
            }
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
        .navigationTitle(String(localized: "settings.storage_network"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                Text(L10n.languageNote)
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.secondaryText)
                LabeledContent(String(localized: "settings.app_name"), value: "PlexiOS")
                LabeledContent(L10n.version, value: AppVersion.displayString)
            }
            Section(String(localized: "settings.native_caps_title")) {
                Text(String(localized: "settings.native_caps_np"))
                    .font(AppTypography.caption)
                Text(String(localized: "settings.native_caps_audio"))
                    .font(AppTypography.caption)
                Text(String(localized: "settings.native_caps_pip"))
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.settingsAbout)
        .navigationBarTitleDisplayMode(.inline)
    }
}
