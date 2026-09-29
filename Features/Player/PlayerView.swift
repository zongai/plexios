import AVKit
import SwiftUI

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

    private var engine: PlaybackEngine { environment.playbackEngine }

    /// Always prefer the engine's current item (updates on autoplay / track switch).
    private var activeItem: PlexMetadata { engine.currentItem ?? metadata }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Native Media Engine → Metal; otherwise AVPlayer layer
            if engine.isNativeBackendActive {
                MetalVideoView(
                    aspectMode: engine.aspectMode,
                    sink: engine.nativeVideoFrameSink,
                    presenter: engine.nativeVideoPresenter,
                    frame: engine.nativeLatestVideoFrame
                )
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }
            } else if engine.isVLCBackendActive, let vlc = engine.vlcBackend {
                VLCPlayerContainer(backend: vlc, aspectMode: engine.aspectMode)
                    .ignoresSafeArea()
                    .onTapGesture { toggleControls() }
            } else if let player = engine.player {
                PlayerLayerView(player: player, aspectMode: engine.aspectMode) { active in
                    isPiPActive = active
                    if active {
                        showControls = false
                    }
                }
                .ignoresSafeArea()
                .onTapGesture { toggleControls() }
            } else if engine.sessionState == .loading {
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel("Loading playback")
            } else if let error = localError ?? engine.errorMessage {
                VStack(spacing: AppSpacing.md) {
                    Text(error)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }

            if showControls && !isPiPActive && (engine.player != nil || engine.isNativeBackendActive) {
                controlsOverlay
                    .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            await startPlayback()
        }
        .onDisappear {
            // Keep playing if PiP is active; otherwise stop.
            if !isPiPActive {
                Task { await engine.stop(report: true) }
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

    private var controlsOverlay: some View {
        VStack {
            HStack {
                Button {
                    Task {
                        await engine.stop(report: true)
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .padding()
                }

                Spacer()

                // AirPlay
                AirPlayRoutePickerView()
                    .frame(width: 44, height: 44)

                if let decision = engine.decision {
                    Text(engine.isNativeBackendActive
                           ? "native · \(decision.mode.rawValue)"
                           : decision.mode.rawValue)
                        .font(AppTypography.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.trailing, 8)
                }
            }

            Spacer()

            HStack(spacing: 48) {
                Button {
                    Task { await engine.skip(seconds: -10) }
                    bumpControls()
                } label: {
                    Image(systemName: "gobackward.10")
                        .font(.title)
                        .foregroundStyle(.white)
                }

                Button {
                    engine.togglePlayPause()
                    bumpControls()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.white)
                }

                Button {
                    Task { await engine.skip(seconds: 10) }
                    bumpControls()
                } label: {
                    Image(systemName: "goforward.10")
                        .font(.title)
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(activeItem.title)
                    .font(AppTypography.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .accessibilityLabel(activeItem.title)

                GeometryReader { geo in
                    let progress = dragProgress ?? playbackProgress
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.3))
                            .frame(height: 4)
                        Capsule()
                            .fill(.white)
                            .frame(width: geo.size.width * progress, height: 4)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let p = min(1, max(0, value.location.x / geo.size.width))
                                dragProgress = p
                                bumpControls()
                            }
                            .onEnded { value in
                                let p = min(1, max(0, value.location.x / geo.size.width))
                                dragProgress = nil
                                let ms = Int64(p * Double(max(engine.durationMs, 1)))
                                Task { await engine.seek(toMs: ms) }
                            }
                    )
                }
                .frame(height: 24)

                HStack {
                    Text(formatTime(engine.positionMs))
                    Spacer()
                    Text(formatTime(engine.durationMs))
                }
                .font(AppTypography.caption)
                .foregroundStyle(.white.opacity(0.8))

                HStack(spacing: AppSpacing.lg) {
                    if !engine.audioStreams.isEmpty {
                        Menu {
                            ForEach(engine.audioStreams, id: \.id) { stream in
                                Button {
                                    Task { await engine.selectAudio(streamId: stream.id) }
                                } label: {
                                    HStack {
                                        Text(stream.displayTitle ?? stream.language ?? "Track \(stream.id)")
                                        if stream.id == engine.selectedAudioId {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("Audio", systemImage: "speaker.wave.2")
                                .foregroundStyle(.white)
                        }
                    }

                    Menu {
                        Button {
                            Task { await engine.selectSubtitle(streamId: nil) }
                        } label: {
                            HStack {
                                Text("Off")
                                if engine.selectedSubtitleId == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        ForEach(engine.subtitleStreams, id: \.id) { stream in
                            Button {
                                Task { await engine.selectSubtitle(streamId: stream.id) }
                            } label: {
                                HStack {
                                    Text(stream.displayTitle ?? stream.language ?? "Sub \(stream.id)")
                                    if stream.id == engine.selectedSubtitleId {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Subtitles", systemImage: "captions.bubble")
                            .foregroundStyle(.white)
                    }

                    // Playback speed
                    Menu {
                        ForEach(PlaybackPreferences.rateOptions, id: \.self) { rate in
                            Button {
                                engine.setPlaybackRate(rate)
                                bumpControls()
                            } label: {
                                HStack {
                                    Text(rateLabel(rate))
                                    if abs(engine.playbackRate - rate) < 0.01 {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label(rateLabel(engine.playbackRate), systemImage: "gauge.with.dots.needle.33percent")
                            .foregroundStyle(.white)
                    }

                    // Aspect ratio
                    Menu {
                        ForEach(VideoAspectMode.allCases) { mode in
                            Button {
                                engine.setAspectMode(mode)
                                bumpControls()
                            } label: {
                                HStack {
                                    Text(mode.title)
                                    if engine.aspectMode == mode {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Aspect", systemImage: engine.aspectMode == .fit ? "rectangle" : "rectangle.arrowtriangle.2.outward")
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Image(systemName: "pip.enter")
                        .foregroundStyle(.white.opacity(0.6))
                        .accessibilityLabel("Picture in Picture available via system controls")
                }
                .font(AppTypography.subheadline)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.xl)
        }
        .background(
            LinearGradient(
                colors: [.black.opacity(0.6), .clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var playbackProgress: Double {
        guard engine.durationMs > 0 else { return 0 }
        return min(1, Double(engine.positionMs) / Double(engine.durationMs))
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
