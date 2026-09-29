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

    /// Grouped channels for Plex-style section rails.
    private var groupedChannels: [(group: String, channels: [IPTVChannel])] {
        let list = vm.filtered
        if let only = vm.selectedGroup {
            return [(only, list)]
        }
        var order: [String] = []
        var buckets: [String: [IPTVChannel]] = [:]
        for ch in list {
            let g = (ch.group?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                ?? String(localized: "iptv.group_other")
            if buckets[g] == nil {
                order.append(g)
                buckets[g] = []
            }
            buckets[g]?.append(ch)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading && vm.channels.isEmpty {
                    LoadingStateView()
                } else if vm.filtered.isEmpty {
                    EmptyStateView(
                        title: String(localized: "iptv.empty_title"),
                        systemImage: "tv",
                        subtitle: String(localized: "iptv.empty")
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
            .background(PlexColors.background)
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
                IPTVPlayerView(session: session, channelList: vm.filtered)
            }
            .sheet(isPresented: $showGuide) {
                IPTVGuideTimelineView(channels: vm.filtered)
            }
        }
    }

    private var channelList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.lg, pinnedViews: [.sectionHeaders]) {
                ForEach(groupedChannels, id: \.group) { section in
                    Section {
                        LazyVStack(spacing: AppSpacing.xs) {
                            ForEach(section.channels) { channel in
                                IPTVChannelRow(
                                    channel: channel,
                                    programTitle: programTitle(for: channel),
                                    programProgress: programProgress(for: channel),
                                    isFavorite: vm.favoriteIds.contains(channel.id),
                                    onPlay: { startPlay(channel) },
                                    onToggleFavorite: {
                                        Task { await vm.toggleFavorite(channel.id) }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                    } header: {
                        Text(section.group)
                            .font(AppTypography.headline.weight(.semibold))
                            .foregroundStyle(PlexColors.primaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, AppSpacing.md)
                            .padding(.vertical, AppSpacing.sm)
                            .background(PlexColors.background.opacity(0.92))
                    }
                }
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .background(PlexColors.background)
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

    private func startPlay(_ channel: IPTVChannel) {
        guard let source = vm.bestSource(for: channel) else { return }
        playSession = IPTVPlaySession(channel: channel, source: source, tried: [source.id])
    }
}

// MARK: - Channel row (Plex visual language)

private struct IPTVChannelRow: View {
    let channel: IPTVChannel
    let programTitle: String?
    let programProgress: Double
    let isFavorite: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: AppSpacing.md) {
                logo

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(AppTypography.body.weight(.semibold))
                        .foregroundStyle(PlexColors.primaryText)
                        .lineLimit(1)

                    if let programTitle, !programTitle.isEmpty {
                        Text(programTitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(PlexColors.secondaryText)
                            .lineLimit(1)

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(PlexColors.surfaceElevated)
                                Capsule()
                                    .fill(PlexColors.accent)
                                    .frame(width: max(4, geo.size.width * programProgress))
                            }
                        }
                        .frame(height: 3)
                        .padding(.top, 2)
                    } else if channel.sources.count > 1 {
                        Text(String(format: String(localized: "iptv.sources_count"), channel.sources.count))
                            .font(AppTypography.caption2)
                            .foregroundStyle(PlexColors.tertiaryText)
                    }
                }

                Spacer(minLength: 4)

                Button(action: onToggleFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(isFavorite ? PlexColors.accent : PlexColors.secondaryText)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Image(systemName: "play.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(PlexColors.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .background(PlexColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: PlexRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var logo: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PlexRadius.sm, style: .continuous)
                .fill(PlexColors.surfaceElevated)
            if channel.logoURL != nil {
                PlexImage(
                    url: channel.logoURL,
                    pointSize: CGSize(width: 56, height: 56),
                    contentMode: .fit
                )
                .padding(6)
            } else {
                Image(systemName: "tv")
                    .font(.title3)
                    .foregroundStyle(PlexColors.tertiaryText)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: PlexRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PlexRadius.sm, style: .continuous)
                .strokeBorder(PlexColors.separator.opacity(0.35), lineWidth: 0.5)
        )
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
    /// Ordered list for previous / next channel (usually current filter).
    var channelList: [IPTVChannel]
    @State private var showSources = false
    @State private var diagnostics = IPTVDiagnostics()
    @State private var bufferingStarted: Date?
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?

    private var engine: PlaybackEngine { environment.playbackEngine }

    private var channelIndex: Int? {
        channelList.firstIndex(where: { $0.id == session.channel.id })
    }

    private var canGoPrevious: Bool {
        guard let i = channelIndex else { return false }
        return i > 0
    }

    private var canGoNext: Bool {
        guard let i = channelIndex else { return false }
        return i + 1 < channelList.count
    }

    var body: some View {
        @Bindable var engine = environment.playbackEngine
        ZStack {
            Color.black.ignoresSafeArea()

            Group {
                if engine.isVLCBackendActive, let vlc = engine.vlcBackend {
                    VLCPlayerContainer(backend: vlc, aspectMode: engine.aspectMode)
                } else if let player = engine.player {
                    PlayerLayerView(player: player, aspectMode: engine.aspectMode) { _ in }
                } else if engine.sessionState == .loading || engine.sessionState == .buffering {
                    ProgressView()
                        .tint(.white)
                } else if let err = engine.errorMessage {
                    Text(err)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }
                .zIndex(5)

            if showControls {
                IPTVPlayerChrome(
                    title: session.channel.name,
                    sourceLabel: session.source.name ?? session.source.quality.displayName,
                    programTitle: currentProgramTitle,
                    groupLabel: session.channel.group,
                    isPlaying: engine.isPlaying,
                    isBuffering: engine.sessionState == .buffering || engine.sessionState == .loading,
                    canGoPrevious: canGoPrevious,
                    canGoNext: canGoNext,
                    sourceCount: session.channel.sources.count,
                    aspectMode: engine.aspectMode,
                    onClose: {
                        Task {
                            await engine.stop(report: false)
                            OrientationLock.unlockAll()
                            dismiss()
                        }
                    },
                    onSources: { showSources = true },
                    onPlayPause: {
                        engine.togglePlayPause()
                        bumpControls()
                    },
                    onPreviousChannel: { switchChannel(delta: -1) },
                    onNextChannel: { switchChannel(delta: 1) },
                    onAspectMode: { mode in
                        engine.setAspectMode(mode)
                        bumpControls()
                    },
                    onToggleHUD: {
                        diagnostics.isVisible.toggle()
                        bumpControls()
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            if diagnostics.isVisible {
                IPTVDiagnosticsHUD(diagnostics: diagnostics)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .zIndex(20)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .background(Color.black)
        .task {
            OrientationLock.lockLandscape()
            let prefs = await IPTVRepository.shared.preferences()
            diagnostics.isVisible = prefs.showDiagnosticsHUD
            diagnostics.reset(
                channel: session.channel.name,
                source: session.source,
                backend: "…"
            )
            await playCurrent()
            try? await Task.sleep(for: .milliseconds(200))
            engine.vlcBackend?.rebindDrawable()
            bumpControls()
        }
        .onDisappear {
            hideControlsTask?.cancel()
            Task { await engine.stop(report: false) }
            OrientationLock.unlockAll()
        }
        .onChange(of: engine.sessionState) { _, state in
            diagnostics.sessionState = String(describing: state)
            diagnostics.estimatedThroughputMbps = engine.estimatedThroughputMbps
            diagnostics.backend = engine.isVLCBackendActive ? "VLC" : (engine.player != nil ? "AVPlayer" : "?")
            switch state {
            case .playing:
                diagnostics.markPlaying()
                bufferingStarted = nil
                engine.vlcBackend?.rebindDrawable()
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

    private var currentProgramTitle: String? { nil }

    private func toggleControls() {
        showControls.toggle()
        if showControls { bumpControls() }
    }

    private func bumpControls() {
        showControls = true
        hideControlsTask?.cancel()
        hideControlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                showControls = false
            }
        }
    }

    private func switchChannel(delta: Int) {
        guard let i = channelIndex else { return }
        let next = i + delta
        guard channelList.indices.contains(next) else { return }
        let ch = channelList[next]
        guard let source = SourceSelectionEngine.select(
            from: ch.sources,
            preferred: .unknown,
            excluding: [],
            estimatedThroughputMbps: nil
        ) ?? ch.sources.first else { return }
        session.channel = ch
        session.source = source
        session.tried = [source.id]
        diagnostics.reset(channel: ch.name, source: source, backend: "…")
        bumpControls()
        Task { await playCurrent() }
    }

    private func playCurrent() async {
        guard let url = session.source.streamURL else {
            diagnostics.markError(String(localized: "iptv.error.invalid_url"))
            return
        }
        diagnostics.backend = "starting"
        diagnostics.redactedURL = IPTVDiagnostics.redact(session.source.streamURLString)
        await engine.playIPTV(
            url: url,
            headers: session.source.headers,
            title: session.channel.name
        )
        diagnostics.backend = engine.isVLCBackendActive ? "VLC" : "AVPlayer"
        try? await Task.sleep(for: .milliseconds(100))
        engine.vlcBackend?.rebindDrawable()
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

/// Plex-style live player chrome: gradient edges, icon-only controls, channel ±.
private struct IPTVPlayerChrome: View {
    let title: String
    let sourceLabel: String
    let programTitle: String?
    let groupLabel: String?
    let isPlaying: Bool
    let isBuffering: Bool
    let canGoPrevious: Bool
    let canGoNext: Bool
    let sourceCount: Int
    let aspectMode: VideoAspectMode
    let onClose: () -> Void
    let onSources: () -> Void
    let onPlayPause: () -> Void
    let onPreviousChannel: () -> Void
    let onNextChannel: () -> Void
    let onAspectMode: (VideoAspectMode) -> Void
    let onToggleHUD: () -> Void

    var body: some View {
        ZStack {
            // Top + bottom scrims (Plex-like)
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [.black.opacity(0.75), .black.opacity(0.0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 120)
                Spacer()
                LinearGradient(
                    colors: [.black.opacity(0.0), .black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 160)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerTransport
                Spacer()
                bottomBar
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
    }

    private var topBar: some View {
        HStack(spacing: AppSpacing.md) {
            chromeIcon("xmark", label: L10n.playerClose, action: onClose)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppTypography.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let groupLabel, !groupLabel.isEmpty {
                        Text(groupLabel)
                            .lineLimit(1)
                    }
                    if let programTitle {
                        if groupLabel != nil { Text("·") }
                        Text(programTitle)
                            .lineLimit(1)
                    }
                }
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.75))
            }

            Spacer(minLength: 8)

            if sourceCount > 1 {
                chromeIcon("rectangle.stack", label: String(localized: "iptv.sources"), action: onSources)
            }
            chromeIcon("info.circle", label: String(localized: "iptv.diagnostics_hud"), action: onToggleHUD)
        }
        .padding(.top, AppSpacing.xs)
    }

    private var centerTransport: some View {
        HStack(spacing: 44) {
            chromeIcon("backward.end.fill", label: String(localized: "iptv.channel_prev"), size: 28, enabled: canGoPrevious, action: onPreviousChannel)

            Button(action: onPlayPause) {
                ZStack {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                    if isBuffering {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)
                    }
                }
            }
            .accessibilityLabel(isPlaying ? L10n.playerPause : L10n.playerPlay)

            chromeIcon("forward.end.fill", label: String(localized: "iptv.channel_next"), size: 28, enabled: canGoNext, action: onNextChannel)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: AppSpacing.md) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
            Text("LIVE")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(sourceLabel)
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
            Spacer(minLength: 8)

            // Aspect ratio — same options as Plex player
            Menu {
                ForEach(VideoAspectMode.allCases) { mode in
                    Button {
                        onAspectMode(mode)
                    } label: {
                        if aspectMode == mode {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                Image(systemName: aspectIconName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "player.aspect"))

            if sourceCount > 1 {
                Text(String(format: String(localized: "iptv.sources_count"), sourceCount))
                    .font(AppTypography.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, AppSpacing.sm)
    }

    private var aspectIconName: String {
        switch aspectMode {
        case .fit: return "rectangle"
        case .fill: return "rectangle.arrowtriangle.2.outward"
        case .stretch: return "arrow.up.left.and.arrow.down.right"
        }
    }

    private func chromeIcon(
        _ systemName: String,
        label: String,
        size: CGFloat = 20,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white.opacity(enabled ? 1 : 0.35))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .buttonStyle(.plain)
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

