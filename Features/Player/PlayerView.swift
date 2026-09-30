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
            // Wait until landscape geometry is applied so VLC drawable is not 0×portrait mid-rotate.
            await waitForLandscapeLayout()
            showControls = true
            await startPlayback()
            // Rebind once the representable has landscape bounds.
            try? await Task.sleep(for: .milliseconds(150))
            engine.vlcBackend?.rebindDrawable()
            bumpControls()
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

    private var controlsOverlay: some View {
        VStack {
            // Top bar — icons only
            HStack(spacing: AppSpacing.md) {
                controlIconButton("xmark", label: L10n.playerClose) {
                    Task {
                        await engine.stop(report: true)
                        OrientationLock.unlockAll()
                        dismiss()
                    }
                }

                Spacer()

                AirPlayRoutePickerView()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(L10n.airPlay)
            }
            .padding(.horizontal, AppSpacing.sm)
            .padding(.top, AppSpacing.sm)

            Spacer()

            // Center transport — icons only
            HStack(spacing: 48) {
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

            Spacer()

            VStack(spacing: AppSpacing.sm) {
                // Scrubber + times (times stay as minimal chrome)
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
                .accessibilityLabel(L10n.playbackPosition)

                HStack {
                    Text(formatTime(engine.positionMs))
                        .monospacedDigit()
                    Spacer()
                    Text(formatTime(engine.durationMs))
                        .monospacedDigit()
                }
                .font(AppTypography.caption2)
                .foregroundStyle(.white.opacity(0.75))

                // Bottom tool row — icon-only menus
                HStack(spacing: AppSpacing.xl) {
                    if !engine.audioStreams.isEmpty {
                        Menu {
                            ForEach(engine.audioStreams, id: \.id) { stream in
                                Button {
                                    Task { await engine.selectAudio(streamId: stream.id) }
                                } label: {
                                    if stream.id == engine.selectedAudioId {
                                        Label(
                                            stream.displayTitle ?? stream.language ?? "Track \(stream.id)",
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text(stream.displayTitle ?? stream.language ?? "Track \(stream.id)")
                                    }
                                }
                            }
                        } label: {
                            controlIcon("speaker.wave.2.fill", label: L10n.audioTracks)
                        }
                    }

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
                                        Label(
                                            stream.displayTitle ?? stream.language ?? "Sub \(stream.id)",
                                            systemImage: "checkmark"
                                        )
                                    } else {
                                        Text(stream.displayTitle ?? stream.language ?? "Sub \(stream.id)")
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

                    Spacer(minLength: 0)
                }
                .padding(.top, AppSpacing.xs)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)
            .padding(.bottom, 8) // extra for landscape home indicator
        }
        .padding(.top, 4)
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
