import SwiftUI

@Observable
@MainActor
final class IPTVViewModel {
    var channels: [IPTVChannel] = []
    var groups: [String] = []
    var selectedGroup: String?
    var searchText = ""
    var isLoading = false
    var errorMessage: String?
    var favoritesOnly = false
    private(set) var favoriteIds: Set<String> = []
    private(set) var quality: IPTVStreamQuality = .unknown
    private(set) var autoSwitch = true
    private(set) var adaptiveQuality = true
    /// channelId → current program title (cached snapshot)
    var nowPlayingTitles: [String: String] = [:]
    var nowPlayingProgress: [String: Double] = [:]

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let repo = IPTVRepository.shared
        let prefs = await repo.preferences()
        favoriteIds = Set(prefs.favoriteChannelIds)
        quality = prefs.defaultQuality
        autoSwitch = prefs.autoSwitchSource
        adaptiveQuality = prefs.adaptiveQuality

        let epgURLs = await repo.epgURLs()
        await EPGRepository.shared.warmCache(for: epgURLs)

        var all = await repo.allEnabledChannels()
        let playlists = await repo.playlists().filter(\.enabled)
        for pl in playlists where pl.channelCount == 0 {
            _ = try? await repo.refreshPlaylist(pl)
        }
        all = await repo.allEnabledChannels()
        channels = all
        groups = Array(Set(all.compactMap(\.group).filter { !$0.isEmpty })).sorted()
        errorMessage = all.isEmpty ? String(localized: "iptv.empty") : nil
        Task {
            await repo.refreshAllEPG(force: false)
        }
    }

    func applyEPGIndex(_ index: EPGChannelIndex) {
        var titles: [String: String] = [:]
        var progress: [String: Double] = [:]
        for ch in channels {
            guard let tvg = ch.tvgID else { continue }
            if let cur = index.current(channelID: tvg) {
                titles[ch.id] = cur.title
                progress[ch.id] = cur.progress()
            }
        }
        nowPlayingTitles = titles
        nowPlayingProgress = progress
    }

    var filtered: [IPTVChannel] {
        var list = channels
        if favoritesOnly {
            list = list.filter { favoriteIds.contains($0.id) }
        }
        if let g = selectedGroup {
            list = list.filter { $0.group == g }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || ($0.tvgID?.lowercased().contains(q) ?? false)
                    || ($0.group?.lowercased().contains(q) ?? false)
                    || (nowPlayingTitles[$0.id]?.lowercased().contains(q) ?? false)
            }
        }
        return list
    }

    func toggleFavorite(_ id: String) async {
        await IPTVRepository.shared.toggleFavorite(channelId: id)
        let prefs = await IPTVRepository.shared.preferences()
        favoriteIds = Set(prefs.favoriteChannelIds)
    }

    func bestSource(for channel: IPTVChannel, excluding: Set<UUID> = [], throughput: Double? = nil) -> IPTVSource? {
        SourceSelectionEngine.select(
            from: channel.sources,
            preferred: quality,
            excluding: excluding,
            estimatedThroughputMbps: adaptiveQuality ? throughput : nil
        )
    }
}

struct IPTVView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var vm = IPTVViewModel()
    @State private var playSession: IPTVPlaySession?
    @State private var epgTick = Date()
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.channels.isEmpty {
                    ProgressView()
                } else if vm.filtered.isEmpty {
                    ContentUnavailableView(
                        String(localized: "iptv.empty_title"),
                        systemImage: "tv",
                        description: Text(String(localized: "iptv.empty"))
                    )
                } else {
                    channelList
                }
            }
            .navigationTitle(String(localized: "iptv.title"))
            .searchable(text: $vm.searchText, prompt: String(localized: "iptv.search"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            vm.favoritesOnly.toggle()
                        } label: {
                            Label(
                                vm.favoritesOnly ? String(localized: "iptv.show_all") : String(localized: "iptv.favorites"),
                                systemImage: "heart"
                            )
                        }
                        Button {
                            showGuide = true
                        } label: {
                            Label(String(localized: "iptv.guide"), systemImage: "list.bullet.rectangle")
                        }
                        Divider()
                        Button(String(localized: "iptv.group_all")) { vm.selectedGroup = nil }
                        ForEach(vm.groups, id: \.self) { g in
                            Button(g) { vm.selectedGroup = g }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .task {
                await vm.reload()
                await refreshEPGLabels()
            }
            .refreshable { await vm.reload() }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { date in
                epgTick = date
                Task { await refreshEPGLabels() }
            }
            .fullScreenCover(item: $playSession) { session in
                IPTVPlayerView(session: session)
            }
            .sheet(isPresented: $showGuide) {
                IPTVGuideTimelineView(channels: vm.filtered)
            }
        }
    }

    private var channelList: some View {
        List(vm.filtered) { channel in
            Button {
                startPlay(channel)
            } label: {
                HStack(spacing: AppSpacing.md) {
                    channelLogo(channel)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.primaryText)
                            .lineLimit(1)
                        if let prog = programTitle(for: channel) {
                            Text(prog)
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.secondaryText)
                                .lineLimit(1)
                            ProgressView(value: programProgress(for: channel))
                                .tint(PlexColors.accent)
                        } else if let g = channel.group {
                            Text(g)
                                .font(AppTypography.caption2)
                                .foregroundStyle(AppColors.secondaryText)
                        }
                    }
                    Spacer()
                    Button {
                        Task { await vm.toggleFavorite(channel.id) }
                    } label: {
                        Image(systemName: vm.favoriteIds.contains(channel.id) ? "heart.fill" : "heart")
                            .foregroundStyle(vm.favoriteIds.contains(channel.id) ? PlexColors.accent : AppColors.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
    }

    private func programTitle(for channel: IPTVChannel) -> String? {
        _ = epgTick
        return vm.nowPlayingTitles[channel.id]
    }

    private func programProgress(for channel: IPTVChannel) -> Double {
        _ = epgTick
        return vm.nowPlayingProgress[channel.id] ?? 0
    }

    private func refreshEPGLabels() async {
        let index = await EPGRepository.shared.index()
        vm.applyEPGIndex(index)
    }

    private func channelLogo(_ channel: IPTVChannel) -> some View {
        Group {
            if let url = channel.logoURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFit()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 48, height: 48)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))
    }

    private var placeholder: some View {
        Image(systemName: "tv")
            .foregroundStyle(AppColors.tertiaryText)
    }

    private func startPlay(_ channel: IPTVChannel) {
        guard let source = vm.bestSource(for: channel) else { return }
        playSession = IPTVPlaySession(channel: channel, source: source, tried: [source.id])
    }
}

struct IPTVPlaySession: Identifiable {
    let id = UUID()
    var channel: IPTVChannel
    var source: IPTVSource
    var tried: Set<UUID>
}

struct IPTVPlayerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State var session: IPTVPlaySession
    @State private var showSources = false
    @State private var diagnostics = IPTVDiagnostics()
    @State private var bufferingStarted: Date?
    @State private var showControls = true

    private var engine: PlaybackEngine { environment.playbackEngine }

    var body: some View {
        PlayerShell {
            Color.clear
            IPTVPlayerChrome(
                title: session.channel.name,
                sourceLabel: session.source.name ?? session.source.quality.displayName,
                programTitle: currentProgramTitle,
                onClose: {
                    Task {
                        await engine.stop(report: false)
                        dismiss()
                    }
                },
                onSources: { showSources = true },
                onPlayPause: { engine.togglePlayPause() },
                onToggleHUD: {
                    diagnostics.isVisible.toggle()
                },
                isPlaying: engine.isPlaying
            )
            .opacity(showControls ? 1 : 0)

            if diagnostics.isVisible {
                IPTVDiagnosticsHUD(diagnostics: diagnostics)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { showControls.toggle() }
        .task {
            let prefs = await IPTVRepository.shared.preferences()
            diagnostics.isVisible = prefs.showDiagnosticsHUD
            diagnostics.reset(
                channel: session.channel.name,
                source: session.source,
                backend: "…"
            )
            await playCurrent()
        }
        .onChange(of: engine.sessionState) { _, state in
            diagnostics.sessionState = String(describing: state)
            diagnostics.estimatedThroughputMbps = engine.estimatedThroughputMbps
            diagnostics.backend = engine.isVLCBackendActive ? "VLC" : (engine.player != nil ? "AVPlayer" : "?")
            switch state {
            case .playing:
                diagnostics.markPlaying()
                bufferingStarted = nil
                Task {
                    await IPTVRepository.shared.recordSourceSuccess(
                        channelId: session.channel.id,
                        sourceId: session.source.id
                    )
                }
            case .buffering:
                diagnostics.markBuffering()
                if bufferingStarted == nil { bufferingStarted = Date() }
                Task { await maybeAdaptiveDowngrade() }
            case .error:
                diagnostics.markError(engine.errorMessage ?? "error")
                Task { await tryNextSource() }
            default:
                break
            }
        }
        .sheet(isPresented: $showSources) {
            NavigationStack {
                List {
                    ForEach(session.channel.sources) { src in
                        Button {
                            session.source = src
                            session.tried.insert(src.id)
                            showSources = false
                            diagnostics.markSourceSwitch(to: src)
                            Task { await playCurrent() }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(src.name ?? src.quality.displayName)
                                    Text(src.streamURL?.host ?? "")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if src.id == session.source.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                .navigationTitle(String(localized: "iptv.sources"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(L10n.close) { showSources = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var currentProgramTitle: String? {
        guard let tvg = session.channel.tvgID else { return nil }
        // Snapshot from last EPG index via async would lag; omit live bind here
        return nil
    }

    private func playCurrent() async {
        guard let url = session.source.streamURL else { return }
        diagnostics.backend = "starting"
        await engine.playIPTV(
            url: url,
            headers: session.source.headers,
            title: session.channel.name
        )
        diagnostics.backend = engine.isVLCBackendActive ? "VLC" : "AVPlayer"
        diagnostics.redactedURL = IPTVDiagnostics.redact(session.source.streamURLString)
    }

    private func tryNextSource() async {
        let prefs = await IPTVRepository.shared.preferences()
        guard prefs.autoSwitchSource else { return }
        await IPTVRepository.shared.recordSourceFailure(
            channelId: session.channel.id,
            sourceId: session.source.id
        )
        let throughput = engine.estimatedThroughputMbps
        guard let next = SourceSelectionEngine.select(
            from: session.channel.sources,
            preferred: prefs.defaultQuality,
            excluding: session.tried,
            estimatedThroughputMbps: prefs.adaptiveQuality ? throughput : nil
        ) else { return }
        session.tried.insert(next.id)
        session.source = next
        diagnostics.markSourceSwitch(to: next)
        await playCurrent()
    }

    private func maybeAdaptiveDowngrade() async {
        let prefs = await IPTVRepository.shared.preferences()
        guard prefs.adaptiveQuality, prefs.autoSwitchSource else { return }
        guard let started = bufferingStarted, Date().timeIntervalSince(started) > 8 else { return }
        let throughput = engine.estimatedThroughputMbps
        let need = SourceSelectionEngine.estimatedNeedMbps(session.source.quality)
        if let throughput, throughput >= need * 0.9, engine.sessionState != .buffering {
            return
        }
        guard let next = SourceSelectionEngine.suggestDowngrade(
            from: session.channel.sources,
            current: session.source,
            excluding: session.tried,
            estimatedThroughputMbps: throughput
        ) else { return }
        session.tried.insert(session.source.id)
        session.tried.insert(next.id)
        session.source = next
        diagnostics.markSourceSwitch(to: next)
        bufferingStarted = nil
        await playCurrent()
    }
}

private struct PlayerShell<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ZStack {
            video
            content
        }
        .statusBarHidden(true)
        .background(Color.black)
    }

    @ViewBuilder
    private var video: some View {
        let engine = environment.playbackEngine
        if engine.isVLCBackendActive, let vlc = engine.vlcBackend {
            VLCPlayerContainer(backend: vlc, aspectMode: engine.aspectMode)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else if let player = engine.player {
            PlayerLayerView(player: player, aspectMode: engine.aspectMode) { _ in }
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

private struct IPTVPlayerChrome: View {
    let title: String
    let sourceLabel: String
    let programTitle: String?
    let onClose: () -> Void
    let onSources: () -> Void
    let onPlayPause: () -> Void
    let onToggleHUD: () -> Void
    let isPlaying: Bool

    var body: some View {
        VStack {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(.white)
                        .padding(12)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text(title)
                        .font(AppTypography.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let programTitle {
                        Text(programTitle)
                            .font(AppTypography.caption2)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    Text(sourceLabel)
                        .font(AppTypography.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Button(action: onToggleHUD) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.white)
                        .padding(8)
                }
                Button(action: onSources) {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(.white)
                        .padding(12)
                }
            }
            .padding(.horizontal)
            Spacer()
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 40)
        }
    }
}

private struct IPTVDiagnosticsHUD: View {
    let diagnostics: IPTVDiagnostics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("IPTV Diagnostics")
                .font(.caption.bold())
            row("Channel", diagnostics.channelName)
            row("Source", diagnostics.sourceName)
            row("Quality", diagnostics.qualityLabel)
            row("Backend", diagnostics.backend)
            row("State", diagnostics.sessionState)
            if let mbps = diagnostics.estimatedThroughputMbps {
                row("Throughput", String(format: "%.1f Mbps", mbps))
            }
            row("Switches", "\(diagnostics.sourceSwitchCount)")
            row("Buffers", "\(diagnostics.bufferEvents)")
            if let ms = diagnostics.startupMs {
                row("Startup", "\(ms) ms")
            }
            if let err = diagnostics.lastError {
                row("Error", err)
            }
            Text(diagnostics.redactedURL)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(3)
        }
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 10))
        .frame(maxWidth: 320, alignment: .leading)
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k + ":")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 72, alignment: .leading)
            Text(v)
                .font(.caption2)
                .lineLimit(2)
        }
    }
}

