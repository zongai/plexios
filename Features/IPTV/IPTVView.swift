import SwiftUI

@Observable
@MainActor
final class IPTVViewModel {
    var channels: [IPTVChannel] = []
    var groups: [String] = []
    var selectedGroup: String? // nil = all
    var searchText = ""
    var isLoading = false
    var errorMessage: String?
    var favoritesOnly = false
    private(set) var favoriteIds: Set<String> = []
    private(set) var quality: IPTVStreamQuality = .unknown
    private(set) var autoSwitch = true

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let repo = IPTVRepository.shared
        let prefs = await repo.preferences()
        favoriteIds = Set(prefs.favoriteChannelIds)
        quality = prefs.defaultQuality
        autoSwitch = prefs.autoSwitchSource
        var all = await repo.allEnabledChannels()
        // Refresh stale playlists in background (best-effort)
        let playlists = await repo.playlists().filter(\.enabled)
        for pl in playlists where pl.channelCount == 0 {
            _ = try? await repo.refreshPlaylist(pl)
        }
        all = await repo.allEnabledChannels()
        channels = all
        groups = Array(Set(all.compactMap(\.group).filter { !$0.isEmpty })).sorted()
        errorMessage = all.isEmpty ? String(localized: "iptv.empty") : nil
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
            }
        }
        return list
    }

    func toggleFavorite(_ id: String) async {
        await IPTVRepository.shared.toggleFavorite(channelId: id)
        let prefs = await IPTVRepository.shared.preferences()
        favoriteIds = Set(prefs.favoriteChannelIds)
    }

    func bestSource(for channel: IPTVChannel, excluding: Set<UUID> = []) -> IPTVSource? {
        SourceSelectionEngine.select(from: channel.sources, preferred: quality, excluding: excluding)
    }
}

struct IPTVView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var vm = IPTVViewModel()
    @State private var playSession: IPTVPlaySession?

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
            .task { await vm.reload() }
            .refreshable { await vm.reload() }
            .fullScreenCover(item: $playSession) { session in
                IPTVPlayerView(session: session)
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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(channel.name)
                            .font(AppTypography.body)
                            .foregroundStyle(AppColors.primaryText)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            if let g = channel.group {
                                Text(g)
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                            Text("\(channel.sources.count) src")
                                .font(AppTypography.caption2)
                                .foregroundStyle(AppColors.tertiaryText)
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

/// Lightweight full-screen IPTV player reusing PlaybackEngine URL path.
struct IPTVPlayerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State var session: IPTVPlaySession
    @State private var showSources = false

    private var engine: PlaybackEngine { environment.playbackEngine }

    var body: some View {
        PlayerShell {
            Color.black.ignoresSafeArea()
            // Reuse same video surfaces as PlayerView via engine state
            IPTVPlayerChrome(
                title: session.channel.name,
                sourceLabel: session.source.name ?? session.source.quality.displayName,
                onClose: {
                    Task {
                        await engine.stop(report: false)
                        dismiss()
                    }
                },
                onSources: { showSources = true },
                onPlayPause: { engine.togglePlayPause() },
                isPlaying: engine.isPlaying
            )
        }
        .task {
            await playCurrent()
        }
        .onChange(of: engine.sessionState) { _, state in
            if state == .error {
                Task { await tryNextSource() }
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

    private func playCurrent() async {
        guard let url = session.source.streamURL else { return }
        await engine.playIPTV(
            url: url,
            headers: session.source.headers,
            title: session.channel.name
        )
    }

    private func tryNextSource() async {
        let prefs = await IPTVRepository.shared.preferences()
        guard prefs.autoSwitchSource else { return }
        await IPTVRepository.shared.recordSourceFailure(
            channelId: session.channel.id,
            sourceId: session.source.id
        )
        guard let next = SourceSelectionEngine.select(
            from: session.channel.sources,
            preferred: prefs.defaultQuality,
            excluding: session.tried
        ) else { return }
        session.tried.insert(next.id)
        session.source = next
        await playCurrent()
    }
}

/// Minimal chrome while full PlayerView is metadata-bound; shows video from engine.
private struct PlayerShell<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        ZStack {
            video
            content
        }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private var video: some View {
        let engine = environment.playbackEngine
        if engine.isVLCBackendActive, let vlc = engine.vlcBackend {
            VLCPlayerContainer(backend: vlc, aspectMode: engine.aspectMode)
                .ignoresSafeArea()
        } else if let player = engine.player {
            PlayerLayerView(player: player, aspectMode: engine.aspectMode) { _ in }
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
    }
}

private struct IPTVPlayerChrome: View {
    let title: String
    let sourceLabel: String
    let onClose: () -> Void
    let onSources: () -> Void
    let onPlayPause: () -> Void
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
                    Text(sourceLabel)
                        .font(AppTypography.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
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
