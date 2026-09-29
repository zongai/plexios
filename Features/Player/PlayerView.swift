import AVKit
import SwiftUI
import UIKit

struct PlayerView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    let metadata: PlexMetadata

    @State private var showControls = true
    @State private var controlsTask: Task<Void, Never>?
    @State private var dragProgress: Double?
    @State private var isPiPActive = false
    @State private var localError: String?
    /// Extra tools (audio/sub/speed/aspect/volume/episodes) collapsed by default.
    @State private var toolsExpanded = false
    @State private var seasonEpisodes: [PlexMetadata] = []
    @State private var showEpisodeSheet = false

    /// Prefer @Bindable so session / isPlaying mutations refresh the chrome.
    private var engine: PlaybackEngine { environment.playbackEngine }

    /// Always prefer the engine's current item (updates on autoplay / track switch).
    private var activeItem: PlexMetadata { engine.currentItem ?? metadata }

    /// True when any backend is presenting video (controls may be shown).
    private var hasActiveVideoSurface: Bool {
        engine.player != nil
            || engine.isNativeBackendActive
            || engine.isVLCBackendActive
            || engine.sessionState == .playing
            || engine.sessionState == .paused
            || engine.sessionState == .buffering
    }

    var body: some View {
        @Bindable var engine = environment.playbackEngine
        ZStack {
            Color.black.ignoresSafeArea()

            // Video surface — no hit testing; taps handled by clear layer above.
            Group {
                if engine.isNativeBackendActive {
                    MetalVideoView(
                        aspectMode: engine.aspectMode,
                        sink: engine.nativeVideoFrameSink,
                        presenter: engine.nativeVideoPresenter,
                        frame: engine.nativeLatestVideoFrame
                    )
                } else if engine.isVLCBackendActive, let vlc = engine.vlcBackend {
                    VLCPlayerContainer(backend: vlc, aspectMode: engine.aspectMode)
                } else if let player = engine.player {
                    PlayerLayerView(player: player, aspectMode: engine.aspectMode) { active in
                        isPiPActive = active
                        if active { showControls = false }
                    }
                } else if engine.sessionState == .loading {
                    ProgressView()
                        .tint(.white)
                        .accessibilityLabel(L10n.loadingPlayback)
                } else if let error = localError ?? engine.errorMessage {
                    VStack(spacing: AppSpacing.md) {
                        Text(error)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                        Button(L10n.close) { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Full-screen tap target (works over VLC UIViewRepresentable).
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }
                .zIndex(5)

            if showControls && !isPiPActive && hasActiveVideoSurface {
                controlsOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            OrientationLock.lockLandscape()
            await waitForLandscapeLayout()
            showControls = true
            await startPlayback()
            try? await Task.sleep(for: .milliseconds(150))
            engine.vlcBackend?.rebindDrawable()
            bumpControls()
            await loadSeasonEpisodes()
        }
        .sheet(isPresented: $showEpisodeSheet) {
            episodePickerSheet
        }
        .onAppear {
            OrientationLock.lockLandscape()
            showControls = true
            bumpControls()
        }
        .onDisappear {
            // Keep playing if PiP is active; otherwise stop.
            if !isPiPActive {
                Task { await engine.stop(report: true) }
            }
            if !isPiPActive {
                OrientationLock.unlockAll()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Background: rely on audio session + PiP; do not stop.
            if phase == .active {
                engine.refreshNowPlaying()
            }
        }
    }

    // MARK: - Controls
    // Layout: top chrome · center transport · bottom timeline (always) · collapsible tools

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topChrome
            Spacer(minLength: 0)
            centerTransport
            Spacer(minLength: 0)
            bottomChrome
        }
        .padding(.top, 4)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var topChrome: some View {
        HStack(spacing: AppSpacing.sm) {
            controlIconButton("xmark", label: L10n.playerClose) {
                Task {
                    await engine.stop(report: true)
                    OrientationLock.unlockAll()
                    dismiss()
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(activeItem.grandparentTitle ?? activeItem.title)
                    .font(AppTypography.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                if activeItem.type == .episode {
                    Text(episodeCaption)
                        .font(AppTypography.caption2)
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            AirPlayRoutePickerView()
                .frame(width: 40, height: 40)
                .accessibilityLabel(L10n.airPlay)

            controlIconButton(
                toolsExpanded ? "chevron.down.circle.fill" : "ellipsis.circle",
                label: String(localized: "player.more_tools")
            ) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    toolsExpanded.toggle()
                }
                bumpControls()
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.top, AppSpacing.sm)
    }

    private var centerTransport: some View {
        HStack(spacing: 44) {
            controlIconButton("gobackward.10", label: L10n.back10, size: 28) {
                Task { await engine.skip(seconds: -10) }
                bumpControls()
            }

            Button {
                engine.togglePlayPause()
                bumpControls()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel(engine.isPlaying ? L10n.playerPause : L10n.playerPlay)

            controlIconButton("goforward.10", label: L10n.forward10, size: 28) {
                Task { await engine.skip(seconds: 10) }
                bumpControls()
            }
        }
    }

    private var bottomChrome: some View {
        VStack(spacing: AppSpacing.sm) {
            if toolsExpanded {
                expandedTools
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Timeline always at the bottom
            timelineBar

            // Compact always-visible row: episodes (if any) + expand hint
            HStack(spacing: AppSpacing.md) {
                if activeItem.type == .episode {
                    Button {
                        showEpisodeSheet = true
                        bumpControls()
                    } label: {
                        controlIcon("list.bullet.rectangle", label: String(localized: "player.episodes"))
                    }
                }

                Spacer(minLength: 0)

                Text(formatTime(engine.positionMs))
                    .font(AppTypography.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                Text(" / ")
                    .font(AppTypography.caption2)
                    .foregroundStyle(.white.opacity(0.45))
                Text(formatTime(engine.durationMs))
                    .font(AppTypography.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.md + 4)
    }

    private var timelineBar: some View {
        GeometryReader { geo in
            let progress = dragProgress ?? playbackProgress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.28))
                    .frame(height: 4)
                Capsule()
                    .fill(.white)
                    .frame(width: max(4, geo.size.width * progress), height: 4)
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .offset(x: max(0, geo.size.width * progress - 6))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = min(1, max(0, value.location.x / max(geo.size.width, 1)))
                        dragProgress = p
                        bumpControls()
                    }
                    .onEnded { value in
                        let p = min(1, max(0, value.location.x / max(geo.size.width, 1)))
                        dragProgress = nil
                        let ms = Int64(p * Double(max(engine.durationMs, 1)))
                        Task { await engine.seek(toMs: ms) }
                    }
            )
        }
        .frame(height: 28)
        .accessibilityLabel(L10n.playbackPosition)
    }

    private var expandedTools: some View {
        VStack(spacing: AppSpacing.md) {
            // Volume
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: engine.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundStyle(.white)
                    .frame(width: 28)
                Slider(
                    value: Binding(
                        get: { Double(engine.volume) },
                        set: { engine.setVolume(Float($0)); bumpControls() }
                    ),
                    in: 0...1
                )
                .tint(.white)
                .accessibilityLabel(String(localized: "player.volume"))
            }
            .padding(.horizontal, 4)

            HStack(spacing: AppSpacing.lg) {
                audioMenu
                subtitleMenu
                speedMenu
                aspectMenu
                if activeItem.type == .episode {
                    Button {
                        showEpisodeSheet = true
                        bumpControls()
                    } label: {
                        controlIcon("rectangle.stack", label: String(localized: "player.episodes"))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, AppSpacing.sm)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: PlexRadius.md, style: .continuous)
                .fill(.black.opacity(0.35))
        )
    }

    @ViewBuilder private var audioMenu: some View {
        if !engine.audioStreams.isEmpty {
            Menu {
                ForEach(engine.audioStreams, id: \.id) { stream in
                    Button {
                        Task { await engine.selectAudio(streamId: stream.id) }
                    } label: {
                        if stream.id == engine.selectedAudioId {
                            Label(stream.displayTitle ?? stream.language ?? "\(stream.id)", systemImage: "checkmark")
                        } else {
                            Text(stream.displayTitle ?? stream.language ?? "\(stream.id)")
                        }
                    }
                }
            } label: {
                controlIcon("speaker.wave.2.fill", label: L10n.audioTracks)
            }
        }
    }

    @ViewBuilder private var subtitleMenu: some View {
        if !engine.subtitleStreams.isEmpty {
            Menu {
                Button {
                    Task { await engine.selectSubtitle(streamId: nil) }
                } label: {
                    if engine.selectedSubtitleId == nil {
                        Label(L10n.off, systemImage: "checkmark")
                    } else {
                        Text(L10n.off)
                    }
                }
                ForEach(engine.subtitleStreams, id: \.id) { stream in
                    Button {
                        Task { await engine.selectSubtitle(streamId: stream.id) }
                    } label: {
                        if stream.id == engine.selectedSubtitleId {
                            Label(stream.displayTitle ?? stream.language ?? "\(stream.id)", systemImage: "checkmark")
                        } else {
                            Text(stream.displayTitle ?? stream.language ?? "\(stream.id)")
                        }
                    }
                }
            } label: {
                controlIcon(
                    engine.selectedSubtitleId == nil ? "captions.bubble" : "captions.bubble.fill",
                    label: L10n.subtitles
                )
            }
        }
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlaybackPreferences.rateOptions, id: \.self) { rate in
                Button {
                    engine.setPlaybackRate(rate)
                    bumpControls()
                } label: {
                    if abs(engine.playbackRate - rate) < 0.01 {
                        Label(rateLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(rateLabel(rate))
                    }
                }
            }
        } label: {
            controlIcon("gauge.with.dots.needle.33percent", label: "\(L10n.speed) \(rateLabel(engine.playbackRate))")
        }
    }

    private var aspectMenu: some View {
        Menu {
            ForEach(VideoAspectMode.allCases) { mode in
                Button {
                    engine.setAspectMode(mode)
                    bumpControls()
                } label: {
                    if engine.aspectMode == mode {
                        Label(mode.title, systemImage: "checkmark")
                    } else {
                        Text(mode.title)
                    }
                }
            }
        } label: {
            controlIcon(
                engine.aspectMode == .fit
                    ? "rectangle"
                    : (engine.aspectMode == .fill ? "rectangle.arrowtriangle.2.outward" : "arrow.up.left.and.arrow.down.right"),
                label: L10n.aspectRatio
            )
        }
    }

    private var episodeCaption: String {
        let code = MediaDisplayFormatting.seasonEpisodeCode(
            season: activeItem.parentIndex,
            episode: activeItem.index
        )
        if let code {
            return "\(code)  \(activeItem.title)"
        }
        return activeItem.title
    }

    private var playbackProgress: Double {
        guard engine.durationMs > 0 else { return 0 }
        return min(1, Double(engine.positionMs) / Double(engine.durationMs))
    }

    private func waitForLandscapeLayout() async {
        for _ in 0..<20 {
            if Task.isCancelled { return }
            if let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene }).first {
                let o = scene.interfaceOrientation
                if o == .landscapeLeft || o == .landscapeRight {
                    try? await Task.sleep(for: .milliseconds(100))
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(200))
    }

    private func startPlayback() async {
        guard let context = environment.serverContext else {
            localError = "No server connected"
            return
        }
        localError = nil
        let network: NetworkClass = {
            if let conn = environment.connectionManager.activeServer?.preferredConnection {
                if conn.relay { return .relay }
                if conn.local { return .lan }
                return .wan
            }
            return .unknown
        }()

        // Seed from prop; engine.currentItem takes over after play / autoplay
        let seed = activeItem
        let full: PlexMetadata
        if seed.media.isEmpty {
            do {
                full = try await environment.metadataRepository.metadata(
                    ratingKey: seed.ratingKey,
                    context: context,
                    force: true
                )
            } catch {
                localError = error.localizedDescription
                return
            }
        } else {
            full = seed
        }

        await engine.play(metadata: full, context: context, network: network, resume: true)
        if engine.errorMessage == nil {
            bumpControls()
        }
        await loadSeasonEpisodes()
    }

    private func loadSeasonEpisodes() async {
        guard activeItem.type == .episode,
              let context = environment.serverContext else {
            seasonEpisodes = []
            return
        }

        // 1) Refresh full metadata — hub/playback payloads often omit parentRatingKey
        var episode = activeItem
        if episode.parentRatingKey == nil || episode.grandparentRatingKey == nil {
            if let full = try? await environment.metadataRepository.metadata(
                ratingKey: episode.ratingKey,
                context: context,
                force: true
            ) {
                episode = full
            }
        }

        // 2) Season children via parentRatingKey
        if let parentKey = episode.parentRatingKey {
            if let kids = try? await environment.metadataRepository.children(
                ratingKey: parentKey,
                context: context
            ) {
                let eps = kids.filter { $0.type == .episode }
                    .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
                if !eps.isEmpty {
                    seasonEpisodes = eps
                    return
                }
            }
        }

        // 3) Show → seasons → match current season by index or membership
        if let showKey = episode.grandparentRatingKey {
            if let seasons = try? await environment.metadataRepository.children(
                ratingKey: showKey,
                context: context
            ) {
                let seasonNodes = seasons.filter { $0.type == .season || $0.type == .unknown }
                // Prefer season matching parentIndex
                var ordered = seasonNodes
                if let si = episode.parentIndex {
                    ordered = seasonNodes.filter { $0.index == si } + seasonNodes.filter { $0.index != si }
                }
                for season in ordered {
                    guard let kids = try? await environment.metadataRepository.children(
                        ratingKey: season.ratingKey,
                        context: context
                    ) else { continue }
                    let eps = kids.filter { $0.type == .episode }
                        .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
                    if eps.contains(where: { $0.ratingKey == episode.ratingKey }) || episode.parentIndex == season.index {
                        if !eps.isEmpty {
                            seasonEpisodes = eps
                            return
                        }
                    }
                    // First non-empty season as weak fallback only if single season
                    if seasonNodes.count == 1, !eps.isEmpty {
                        seasonEpisodes = eps
                        return
                    }
                }
                // If membership match failed, use first season with episodes that share parentIndex
                if let si = episode.parentIndex {
                    for season in seasonNodes where season.index == si {
                        if let kids = try? await environment.metadataRepository.children(
                            ratingKey: season.ratingKey,
                            context: context
                        ) {
                            let eps = kids.filter { $0.type == .episode }
                                .sorted { ($0.index ?? 0) < ($1.index ?? 0) }
                            if !eps.isEmpty {
                                seasonEpisodes = eps
                                return
                            }
                        }
                    }
                }
            }
        }

        // 4) Related hubs — collect episode-like items as a last-resort list
        if let hubs = try? await environment.apiClient.fetchRelated(
            ratingKey: episode.ratingKey,
            baseURL: context.baseURL,
            token: context.token
        ) {
            var seen = Set<String>()
            var collected: [PlexMetadata] = []
            for hub in hubs {
                for item in hub.items where item.type == .episode {
                    if seen.insert(item.ratingKey).inserted {
                        collected.append(item)
                    }
                }
            }
            if !collected.isEmpty {
                seasonEpisodes = collected.sorted { ($0.index ?? 0) < ($1.index ?? 0) }
                return
            }
        }

        seasonEpisodes = []
    }

    private var episodePickerSheet: some View {
        NavigationStack {
            List {
                ForEach(seasonEpisodes) { ep in
                    Button {
                        showEpisodeSheet = false
                        Task {
                            guard let context = environment.serverContext else { return }
                            let network: NetworkClass = {
                                if let conn = environment.connectionManager.activeServer?.preferredConnection {
                                    if conn.relay { return .relay }
                                    if conn.local { return .lan }
                                    return .wan
                                }
                                return .unknown
                            }()
                            await engine.play(metadata: ep, context: context, network: network, resume: false)
                            await loadSeasonEpisodes()
                            bumpControls()
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(MediaDisplayFormatting.seasonEpisodeCode(
                                    season: ep.parentIndex ?? activeItem.parentIndex,
                                    episode: ep.index
                                ) ?? "")
                                .font(AppTypography.caption)
                                .foregroundStyle(AppColors.secondaryText)
                                Text(ep.title)
                                    .font(AppTypography.body)
                                    .foregroundStyle(AppColors.primaryText)
                            }
                            Spacer()
                            if ep.ratingKey == activeItem.ratingKey {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(PlexColors.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "player.episodes"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.close) { showEpisodeSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }


    private func controlIcon(_ systemName: String, label: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
            .accessibilityLabel(label)
    }

    private func controlIconButton(
        _ systemName: String,
        label: String,
        size: CGFloat = 20,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func backendLabel(for decision: PlaybackDecision) -> String {
        if engine.isVLCBackendActive { return "vlc · \(decision.mode.rawValue)" }
        if engine.isNativeBackendActive { return "native · \(decision.mode.rawValue)" }
        return decision.mode.rawValue
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showControls.toggle()
        }
        if showControls { bumpControls() }
    }

    private func bumpControls() {
        controlsTask?.cancel()
        showControls = true
        controlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if engine.isPlaying {
                withAnimation { showControls = false }
            }
        }
    }

    private func formatTime(_ ms: Int64) -> String {
        let total = Int(ms / 1000)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    private func rateLabel(_ rate: Float) -> String {
        if abs(rate - 1.0) < 0.01 { return "1x" }
        if rate == Float(Int(rate)) {
            return "\(Int(rate))x"
        }
        return String(format: "%.2gx", rate)
    }
}
