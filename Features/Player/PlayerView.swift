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
    /// Right-side panels (reference-style floating menus).
    @State private var showSettingsPanel = false
    @State private var showEpisodePanel = false
    @State private var seasonEpisodes: [PlexMetadata] = []

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
                .onTapGesture {
                    if showSettingsPanel || showEpisodePanel {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showSettingsPanel = false
                            showEpisodePanel = false
                        }
                        bumpControls()
                    } else {
                        toggleControls()
                    }
                }
                .zIndex(5)

            if showControls && !isPiPActive && hasActiveVideoSurface {
                controlsOverlay
                    .transition(.opacity)
                    .zIndex(10)
            }

            // Right-side floating panels (settings / episodes)
            if showSettingsPanel && !isPiPActive {
                settingsSidePanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(20)
            }
            if showEpisodePanel && !isPiPActive {
                episodeSidePanel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(20)
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
        .onAppear {
            OrientationLock.lockLandscape()
            showControls = true
            bumpControls()
        }
        .onDisappear {
            if !isPiPActive {
                Task { await engine.stop(report: true) }
            }
            if !isPiPActive {
                OrientationLock.unlockAll()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                engine.refreshNowPlaying()
            }
        }
    }

    // MARK: - Controls (reference layout)
    // Top: close · aspect ········· volume slider
    // Center: −10 · play/pause · +10
    // Bottom: title/meta ····· gear · AirPlay · episodes
    //         progress bar
    //         current ············· −remaining

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            topChrome
            Spacer(minLength: 0)
            if !showSettingsPanel && !showEpisodePanel {
                centerTransport
            }
            Spacer(minLength: 0)
            bottomChrome
        }
        .padding(.top, 8)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.5), .clear, .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var topChrome: some View {
        HStack(spacing: 8) {
            controlIconButton("xmark", label: L10n.playerClose) {
                Task {
                    await engine.stop(report: true)
                    OrientationLock.unlockAll()
                    dismiss()
                }
            }

            // Aspect / fill cycle (reference: top-left secondary control)
            controlIconButton(
                aspectIconName,
                label: L10n.aspectRatio
            ) {
                cycleAspectMode()
                bumpControls()
            }

            Spacer(minLength: 12)

            // Compact volume slider (0…200%; boost >100% effective on VLC)
            HStack(spacing: 8) {
                Text("\(Int((engine.volume * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(engine.volume > 1.01 ? Color.orange : .white.opacity(0.85))
                    .monospacedDigit()
                    .frame(width: 40, alignment: .trailing)

                Slider(
                    value: Binding(
                        get: { Double(engine.volume) },
                        set: { engine.setVolume(Float($0)); bumpControls() }
                    ),
                    in: 0...Double(PlaybackEngine.maxVolume)
                )
                .tint(engine.volume > 1.01 ? .orange : .white)
                .frame(width: 120)
                .accessibilityLabel(String(localized: "player.volume"))
                .accessibilityValue("\(Int((engine.volume * 100).rounded()))%")

                Image(systemName: volumeIconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(engine.volume > 1.01 ? Color.orange : .white.opacity(0.9))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.35))
            )
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var centerTransport: some View {
        HStack(spacing: 48) {
            controlIconButton("gobackward.10", label: L10n.back10, size: 30) {
                Task { await engine.skip(seconds: -10) }
                bumpControls()
            }

            Button {
                engine.togglePlayPause()
                bumpControls()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .accessibilityLabel(engine.isPlaying ? L10n.playerPause : L10n.playerPlay)

            controlIconButton("goforward.10", label: L10n.forward10, size: 30) {
                Task { await engine.skip(seconds: 10) }
                bumpControls()
            }
        }
    }

    private var bottomChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    if activeItem.type == .episode {
                        Text(episodeCaption)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.white.opacity(0.75))
                            .lineLimit(1)
                    }
                    Text(primaryTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    controlIconButton("gearshape.fill", label: String(localized: "player.more_tools"), size: 18) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showEpisodePanel = false
                            showSettingsPanel.toggle()
                        }
                        bumpControls()
                    }

                    AirPlayRoutePickerView()
                        .frame(width: 40, height: 40)
                        .accessibilityLabel(L10n.airPlay)

                    if activeItem.type == .episode {
                        controlIconButton("list.bullet.rectangle", label: String(localized: "player.episodes"), size: 18) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showSettingsPanel = false
                                showEpisodePanel.toggle()
                            }
                            bumpControls()
                        }
                    }
                }
            }

            timelineBar

            HStack {
                Text(formatTime(engine.positionMs))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(remainingTimeLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    private var timelineBar: some View {
        GeometryReader { geo in
            let progress = dragProgress ?? playbackProgress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.22))
                    .frame(height: 3)
                Capsule()
                    .fill(.white)
                    .frame(width: max(3, geo.size.width * progress), height: 3)
                Circle()
                    .fill(.white)
                    .frame(width: 11, height: 11)
                    .offset(x: max(0, geo.size.width * progress - 5.5))
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
        .frame(height: 22)
        .accessibilityLabel(L10n.playbackPosition)
    }

    // MARK: - Settings side panel (reference)

    private var settingsSidePanel: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                settingsRow(
                    title: String(localized: "player.audio_boost"),
                    trailing: "\(Int((engine.volume * 100).rounded()))%",
                    systemImage: engine.volume > 1.01 ? "speaker.wave.3.fill" : "speaker.wave.2.fill"
                ) {
                    // Cycle: 100% → 125% → 150% → 200% → 100% (true boost on VLC)
                    let next: Float
                    if engine.volume < 1.05 { next = 1.25 }
                    else if engine.volume < 1.3 { next = 1.5 }
                    else if engine.volume < 1.75 { next = 2.0 }
                    else { next = 1.0 }
                    engine.setVolume(next)
                    bumpControls()
                }

                settingsMenuRow(
                    title: rateLabel(engine.playbackRate),
                    systemImage: "clock.arrow.circlepath"
                ) {
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
                }

                if !engine.audioStreams.isEmpty {
                    settingsMenuRow(
                        title: currentAudioLabel,
                        systemImage: "music.note"
                    ) {
                        ForEach(engine.audioStreams, id: \.id) { stream in
                            Button {
                                Task { await engine.selectAudio(streamId: stream.id) }
                                bumpControls()
                            } label: {
                                if stream.id == engine.selectedAudioId {
                                    Label(streamLabel(stream), systemImage: "checkmark")
                                } else {
                                    Text(streamLabel(stream))
                                }
                            }
                        }
                    }
                }

                settingsMenuRow(
                    title: currentSubtitleLabel,
                    systemImage: "captions.bubble"
                ) {
                    Button {
                        Task { await engine.selectSubtitle(streamId: nil) }
                        bumpControls()
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
                            bumpControls()
                        } label: {
                            if stream.id == engine.selectedSubtitleId {
                                Label(streamLabel(stream), systemImage: "checkmark")
                            } else {
                                Text(streamLabel(stream))
                            }
                        }
                    }
                }

                settingsMenuRow(
                    title: String(localized: "player.advanced"),
                    systemImage: "gearshape"
                ) {
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
                }
            }
            .frame(width: 260)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .padding(.trailing, 16)
            .padding(.top, 56)
            .padding(.bottom, 100)
        }
        .allowsHitTesting(true)
    }

    private func settingsRow(
        title: String,
        trailing: String?,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func settingsMenuRow<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chevron.forward")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Episode side panel (reference)

    private var episodeSidePanel: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 0) {
                Text(activeItem.grandparentTitle ?? activeItem.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 8)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(seasonEpisodes) { ep in
                            Button {
                                Task {
                                    guard let context = environment.serverContext else { return }
                                    let network = currentNetworkClass()
                                    await engine.play(
                                        metadata: ep,
                                        context: context,
                                        network: network,
                                        resume: false
                                    )
                                    await loadSeasonEpisodes()
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showEpisodePanel = false
                                    }
                                    bumpControls()
                                }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    if ep.ratingKey == activeItem.ratingKey {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                            .frame(width: 14)
                                    } else {
                                        Color.clear.frame(width: 14)
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(episodeRowTitle(ep))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.leading)
                                        Text(ep.title)
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(.white.opacity(0.5))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .padding(.trailing, 16)
            .padding(.top, 56)
            .padding(.bottom, 24)
        }
        .allowsHitTesting(true)
    }

    // MARK: - Labels / helpers

    private var primaryTitle: String {
        if activeItem.type == .episode {
            return activeItem.grandparentTitle ?? activeItem.title
        }
        return activeItem.title
    }

    private var episodeCaption: String {
        let code = MediaDisplayFormatting.seasonEpisodeCode(
            season: activeItem.parentIndex,
            episode: activeItem.index
        )
        if let code {
            return "\(code) - \(activeItem.title)"
        }
        return activeItem.title
    }

    private func episodeRowTitle(_ ep: PlexMetadata) -> String {
        let code = MediaDisplayFormatting.seasonEpisodeCode(
            season: ep.parentIndex ?? activeItem.parentIndex,
            episode: ep.index
        )
        if let code {
            return "\(code) - \(ep.title)"
        }
        return ep.title
    }

    private var currentAudioLabel: String {
        if let id = engine.selectedAudioId,
           let stream = engine.audioStreams.first(where: { $0.id == id }) {
            return streamLabel(stream)
        }
        return L10n.audioTracks
    }

    private var currentSubtitleLabel: String {
        if let id = engine.selectedSubtitleId,
           let stream = engine.subtitleStreams.first(where: { $0.id == id }) {
            return streamLabel(stream)
        }
        if engine.subtitleStreams.isEmpty {
            return L10n.subtitles
        }
        return L10n.off
    }

    private func streamLabel(_ stream: PlexStream) -> String {
        stream.displayTitle ?? stream.language ?? "\(stream.id)"
    }

    private var aspectIconName: String {
        switch engine.aspectMode {
        case .fit: return "arrow.up.left.and.arrow.down.right"
        case .fill: return "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left"
        case .stretch: return "rectangle.ratio.16.to.9"
        }
    }

    private var volumeIconName: String {
        if engine.volume < 0.01 { return "speaker.slash.fill" }
        if engine.volume > 1.01 { return "speaker.wave.3.fill" }
        if engine.volume < 0.4 { return "speaker.wave.1.fill" }
        return "speaker.wave.2.fill"
    }

    private func cycleAspectMode() {
        let all = VideoAspectMode.allCases
        guard let idx = all.firstIndex(of: engine.aspectMode) else {
            engine.setAspectMode(.fit)
            return
        }
        let next = all[(idx + 1) % all.count]
        engine.setAspectMode(next)
    }

    private var remainingTimeLabel: String {
        let remain = max(0, engine.durationMs - engine.positionMs)
        return "-\(formatTime(remain))"
    }

    private var playbackProgress: Double {
        guard engine.durationMs > 0 else { return 0 }
        return min(1, Double(engine.positionMs) / Double(engine.durationMs))
    }

    private func currentNetworkClass() -> NetworkClass {
        if let conn = environment.connectionManager.activeServer?.preferredConnection {
            if conn.relay { return .relay }
            if conn.local { return .lan }
            return .wan
        }
        return .unknown
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
            localError = L10n.noServer
            environment.logger.playback.error("startPlayback: no server context")
            return
        }
        localError = nil
        let network = currentNetworkClass()
        let seed = activeItem
        environment.logger.playback.info(
            "startPlayback seed type=\(seed.type.rawValue) key=\(seed.ratingKey) mediaCount=\(seed.media.count) parts=\(seed.media.map { $0.parts.count }) network=\(String(describing: network))"
        )

        let full: PlexMetadata
        if seed.media.isEmpty {
            do {
                full = try await environment.metadataRepository.metadata(
                    ratingKey: seed.ratingKey,
                    context: context,
                    force: true
                )
                environment.logger.playback.info(
                    "startPlayback fetched metadata mediaCount=\(full.media.count) parts=\(full.media.map { $0.parts.count })"
                )
            } catch {
                localError = error.localizedDescription
                environment.logger.playback.error(
                    "startPlayback metadata fetch failed: \(error.localizedDescription)"
                )
                return
            }
        } else {
            full = seed
            environment.logger.playback.info("startPlayback using seed media (non-empty)")
        }

        await engine.play(metadata: full, context: context, network: network, resume: true)
        if let err = engine.errorMessage {
            environment.logger.playback.error("startPlayback engine error: \(err)")
        } else {
            let backend: String
            if engine.isVLCBackendActive { backend = "vlc" }
            else if engine.isNativeBackendActive { backend = "native" }
            else { backend = "avplayer" }
            environment.logger.playback.info(
                "startPlayback engine OK backend=\(backend) state=\(String(describing: engine.sessionState))"
            )
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

        if let showKey = episode.grandparentRatingKey {
            if let seasons = try? await environment.metadataRepository.children(
                ratingKey: showKey,
                context: context
            ) {
                let seasonNodes = seasons.filter { $0.type == .season || $0.type == .unknown }
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
                    if seasonNodes.count == 1, !eps.isEmpty {
                        seasonEpisodes = eps
                        return
                    }
                }
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

    private func controlIconButton(
        _ systemName: String,
        label: String,
        size: CGFloat = 18,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if showControls {
                showSettingsPanel = false
                showEpisodePanel = false
            }
            showControls.toggle()
        }
        if showControls { bumpControls() }
    }

    private func bumpControls() {
        controlsTask?.cancel()
        showControls = true
        // Keep chrome visible while a side panel is open
        if showSettingsPanel || showEpisodePanel { return }
        controlsTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            if engine.isPlaying, !showSettingsPanel, !showEpisodePanel {
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
