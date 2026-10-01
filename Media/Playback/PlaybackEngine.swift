import AVFoundation
import Foundation
import MediaPlayer
import Observation

/// Owns AVPlayer lifecycle, decision application, session reporting,
/// remote commands, Now Playing, and audio session coordination.
@Observable
@MainActor
final class PlaybackEngine {
    // MARK: - Published state for UI

    private(set) var player: AVPlayer?
    private(set) var sessionState: PlaybackSessionState = .idle
    private(set) var currentItem: PlexMetadata?
    private(set) var decision: PlaybackDecision?
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var isBuffering = false
    private(set) var errorMessage: String?
    private(set) var audioStreams: [PlexStream] = []
    private(set) var subtitleStreams: [PlexStream] = []
    private(set) var selectedAudioId: Int?
    private(set) var selectedSubtitleId: Int?
    /// Playback rate (1.0 = normal). Applied to AVPlayer when playing.
    private(set) var playbackRate: Float = 1.0
    /// How video is scaled inside the player layer.
    private(set) var aspectMode: VideoAspectMode = .fit

    /// Explicit play intent for UI — not derived from sessionState alone.
    /// VLC reports `.buffering` often while still "playing"; icon must stay as pause.
    private(set) var isPlaying: Bool = false

    /// Observed network throughput in Mbps (AVPlayer access log); nil if unknown.
    private(set) var estimatedThroughputMbps: Double?
    private var accessLogObserver: NSObjectProtocol?
    private var throughputSamples: [Double] = []

    // MARK: - Dependencies

    private let decisionEngine: PlaybackDecisionEngine
    private let timelineReporter: TimelineReporter
    private let http: HTTPClient
    private let logger: LogRouter
    private let clientIdentifier: String
    private let identityHeaders: [String: String]

    private let remoteCommands = RemoteCommandController()
    private let audioSession: AudioSessionCoordinator
    private let nowPlaying: NowPlayingController

    private var session: PlaybackSession?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var context: ServerContext?
    private var networkClass: NetworkClass = .unknown
    private var reportTask: Task<Void, Never>?
    private var artworkURL: URL?
    /// Phase 1: diagnostics / future native routing (default path unchanged).
    var playerEngineRouter: PlayerEngineRouter?
    private(set) var lastDiagnostics: PlaybackDiagnostics?
    private(set) var activePlaybackBackend: PlaybackBackend = .avPlayer

    var isNativeBackendActive: Bool { activePlaybackBackend == .nativeMediaEngine }
    var isVLCBackendActive: Bool { activePlaybackBackend == .vlc }

    /// Shared VLC backend instance (drawable bound by PlayerView).
    private(set) var vlcBackend: VLCPlaybackBackend?

    var nativeVideoFrameSink: VideoFrameSink? {
        guard isNativeBackendActive else { return nil }
        return playerEngineRouter?.nativeBackendInstance().videoFrameSink
    }

    var nativeLatestVideoFrame: VideoFrame? {
        nativeVideoFrameSink?.latestFrame
    }

    var nativeVideoPresenter: MetalVideoRenderer.Presenter? {
        guard isNativeBackendActive else { return nil }
        return playerEngineRouter?.nativeBackendInstance().videoPresenter
    }
    private var nativeTimelineTask: Task<Void, Never>?
    private(set) var nativeSystemBridge: NativeSystemMediaBridge?

    init(
        decisionEngine: PlaybackDecisionEngine = PlaybackDecisionEngine(),
        timelineReporter: TimelineReporter,
        http: HTTPClient,
        logger: LogRouter,
        clientIdentifier: String,
        identityHeaders: [String: String]
    ) {
        self.decisionEngine = decisionEngine
        self.timelineReporter = timelineReporter
        self.http = http
        self.logger = logger
        self.clientIdentifier = clientIdentifier
        self.identityHeaders = identityHeaders
        self.audioSession = AudioSessionCoordinator(logger: logger)
        self.nowPlaying = NowPlayingController(logger: logger)

        remoteCommands.attach(to: self)
        audioSession.attach(to: self)
    }

    // MARK: - Intents

    func play(
        metadata: PlexMetadata,
        context: ServerContext,
        network: NetworkClass = .lan,
        preferences: PlaybackPreferences = .default,
        resume: Bool = true,
        forcedAudioId: Int? = nil,
        forcedSubtitleId: Int? = nil
    ) async {
        // Do not fan out Home "continue watching" refresh while opening the player.
        logger.playback.info(
            "play() begin type=\(metadata.type.rawValue) key=\(metadata.ratingKey) title=\(metadata.title) mediaCount=\(metadata.media.count) parts=\(metadata.media.map { $0.parts.count }) network=\(String(describing: network)) resume=\(resume)"
        )
        await stop(report: true, notifyLibraryProgress: false)

        self.context = context
        self.networkClass = network
        self.currentItem = metadata
        self.errorMessage = nil
        isPlaying = false
        sessionState = .loading

        // Always use persisted user defaults for decision + start rate/aspect
        let effectivePrefs = PlaybackSettingsStore.shared.preferences
        playbackRate = effectivePrefs.defaultPlaybackRate
        aspectMode = effectivePrefs.defaultAspectMode

        let engine = PlaybackDecisionEngine.make(preferences: effectivePrefs)
        let decision = engine.decide(
            metadata: metadata,
            network: network,
            forcedAudioId: forcedAudioId,
            forcedSubtitleId: forcedSubtitleId
        )
        self.decision = decision
        logger.playback.info(
            "Decision: \(decision.mode.rawValue) — \(decision.reason) mediaIdx=\(decision.mediaIndex) partIdx=\(decision.partIndex) vlcAllowed=\(effectivePrefs.allowVLCPlayer) preferSystem=\(effectivePrefs.preferSystemPlayer)"
        )
        if let router = playerEngineRouter {
            let report = router.resolve(metadata: metadata, decision: decision, network: network)
            // Metadata-only probe on the play path. Full HTTP Range/container sniffing has
            // caused hard crashes on some files; keep it out of the critical path.
            let probe = MediaProbe().probeFromPlexMetadata(
                metadata,
                mediaIndex: decision.mediaIndex,
                partIndex: decision.partIndex
            )
            lastDiagnostics = PlaybackDiagnostics.from(info: probe, decision: decision, report: report)
            if let line = lastDiagnostics?.displayLines.joined(separator: " · ") {
                logger.playback.info("Diagnostics: \(line)")
            }
        }

        guard let media = metadata.media[safe: decision.mediaIndex],
              let part = media.parts[safe: decision.partIndex]
        else {
            fail("Media part unavailable")
            return
        }

        audioStreams = part.streams.filter { $0.streamType == .audio }
        subtitleStreams = part.streams.filter { $0.streamType == .subtitle }
        selectedAudioId = decision.selectedAudioStreamId
        selectedSubtitleId = decision.selectedSubtitleStreamId

        let duration = metadata.duration ?? part.duration ?? media.duration ?? 0
        durationMs = duration

        let startMs: Int64 = {
            guard resume, let offset = metadata.viewOffset, offset > 0 else { return 0 }
            if duration > 0, Double(offset) / Double(duration) > 0.95 { return 0 }
            return offset
        }()
        positionMs = startMs

        let builder = PlaybackURLBuilder(
            baseURL: context.baseURL,
            token: context.token,
            clientIdentifier: clientIdentifier,
            identityHeaders: identityHeaders
        )

        let sessionId = UUID().uuidString.lowercased()
        guard let url = builder.playbackURL(
            metadata: metadata,
            part: part,
            decision: decision,
            sessionId: sessionId,
            offsetMs: startMs,
            network: network
        ) else {
            fail("Could not build playback URL")
            return
        }

        let newSession = PlaybackSession(
            sessionId: sessionId,
            ratingKey: metadata.ratingKey,
            metadataKey: metadata.key,
            durationMs: duration,
            decision: decision,
            startPositionMs: startMs,
            reportIntervalSeconds: network == .lan ? 10 : 20
        )
        await newSession.updateState(.loading)
        session = newSession

        do {
            try audioSession.activate()
        } catch {
            // Non-fatal — VLC/AVPlayer can still open; log and continue.
            logger.playback.error("Audio session: \(error.localizedDescription) (continuing)")
        }

        artworkURL = PlexImageURL.resolve(
            path: metadata.thumb ?? metadata.art,
            baseURL: context.baseURL,
            token: context.token,
            width: 600,
            height: 900
        )

        // Prefer MobileVLCKit Direct Play when enabled (broad codec/container support).
        let useVLC = decision.mode == .directPlay
            && effectivePrefs.allowVLCPlayer
            && !effectivePrefs.preferSystemPlayer
            && VLCPlaybackBackend.isLinked

        if useVLC {
            do {
                let vlc = vlcBackend ?? VLCPlaybackBackend()
                vlcBackend = vlc
                // Match IPTV: expose backend before prepare so SwiftUI can mount drawable.
                activePlaybackBackend = .vlc
                playerEngineRouter?.markActive(.vlc)
                vlc.onTimeChange = { [weak self] pos, dur in
                    Task { @MainActor in
                        guard let self else { return }
                        self.positionMs = pos
                        if dur > 0 { self.durationMs = dur }
                        self.nowPlaying.updateProgress(
                            positionMs: pos, durationMs: self.durationMs, isPlaying: self.isPlaying
                        )
                    }
                }
                vlc.onEnded = { [weak self] in
                    Task { await self?.handlePlaybackEnded() }
                }
                vlc.onError = { [weak self] message in
                    Task { @MainActor in
                        self?.logger.playback.error("VLC: \(message)")
                        self?.errorMessage = message
                        self?.sessionState = .error
                        self?.isPlaying = false
                    }
                }
                vlc.onStateChange = { [weak self] st in
                    Task { @MainActor in
                        guard let self else { return }
                        switch st {
                        case .playing:
                            self.sessionState = .playing
                            self.isPlaying = true
                        case .paused:
                            self.sessionState = .paused
                            self.isPlaying = false
                        case .buffering:
                            self.sessionState = .buffering
                        case .failed:
                            self.sessionState = .error
                            self.isPlaying = false
                        default:
                            break
                        }
                    }
                }
                var headers = identityHeaders
                headers["X-Plex-Token"] = context.token
                let videoCodec = (media.videoCodec
                    ?? media.parts.first?.streams.first(where: { $0.streamType == .video })?.codec
                    ?? "")
                    .lowercased()
                // Logs: HEVC dies after "VLC prepare returned OK"; H264/VP9 survive.
                // MobileVLCKit + VideoToolbox HEVC is a known hard-crash path — force SW.
                let forceSW = videoCodec.contains("hevc") || videoCodec.contains("h265")
                    || videoCodec.contains("vp9") || videoCodec == "av1"
                // Mid-stream resume seek during HEVC open also correlates with crashes.
                let prepareStartMs: Int64 = forceSW && startMs > 0 ? 0 : startMs
                // Preload at most the preferred sidecar — attaching many slaves at open
                // left VLC unstable and correlated with later audio-track crashes.
                let externalSubs: [URL] = {
                    guard let pref = decision.selectedSubtitleStreamId,
                          let stream = subtitleStreams.first(where: { $0.id == pref }),
                          Self.isSidecarSubtitle(stream),
                          let url = Self.externalSubtitleURL(
                            stream: stream,
                            baseURL: context.baseURL,
                            token: context.token
                          )
                    else { return [] }
                    return [url]
                }()
                logger.playback.info(
                    "VLC prepare begin codec=\(videoCodec) forceSW=\(forceSW) startMs=\(startMs) prepareStartMs=\(prepareStartMs) externalSubs=\(externalSubs.count) url=\(LogRedaction.redactURL(url))"
                )
                try? await Task.sleep(for: .milliseconds(80))
                let audioOrder = decision.selectedAudioStreamId.flatMap { id in
                    audioStreams.firstIndex(where: { $0.id == id })
                }
                let embeddedSubs = subtitleStreams.filter { !Self.isSidecarSubtitle($0) }
                let subOrder = decision.selectedSubtitleStreamId.flatMap { id in
                    embeddedSubs.firstIndex(where: { $0.id == id })
                }
                logger.playback.info(
                    "VLC track prefs audioOrder=\(audioOrder.map(String.init) ?? "nil") subOrder=\(subOrder.map(String.init) ?? "nil") subId=\(decision.selectedSubtitleStreamId.map(String.init) ?? "off") embeddedSubs=\(embeddedSubs.count) sidecar=\(externalSubs.count)"
                )
                try await vlc.prepare(
                    url: url,
                    headers: headers,
                    startPositionMs: prepareStartMs,
                    externalSubtitles: externalSubs,
                    preferredSubtitlePlexId: decision.selectedSubtitleStreamId,
                    preferredAudioPlexId: decision.selectedAudioStreamId,
                    preferredAudioOrder: audioOrder,
                    preferredSubtitleOrder: subOrder,
                    subtitleFontSize: effectivePrefs.subtitleTextSize.freetypeRelFontsize,
                    forceSoftwareDecode: forceSW
                )
                logger.playback.info("VLC prepare returned OK forceSW=\(forceSW)")
                FileLogStore.shared.flush()
                vlc.setRate(playbackRate)
                vlc.setAspectMode(aspectMode)
                if forceSW, startMs > 0 {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1200))
                        self.logger.playback.info("VLC deferred resume seek to \(startMs)ms")
                        await self.vlcBackend?.seek(toMs: startMs)
                    }
                }
                activePlaybackBackend = .vlc
                playerEngineRouter?.markActive(.vlc)
                await newSession.updateState(.playing)
                isPlaying = true
                sessionState = .playing
                startPeriodicReporting()
                publishNowPlaying()
                logger.playback.info(
                    "Playing via MobileVLCKit codec=\(videoCodec) forceSW=\(forceSW) subs=\(decision.selectedSubtitleStreamId.map(String.init) ?? "off") externals=\(externalSubs.count)"
                )
                FileLogStore.shared.flush()
                return
            } catch {
                logger.playback.info("VLC failed, trying other backends: \(error.localizedDescription)")
                activePlaybackBackend = .avPlayer
            }
        }

        // Optional Native Media Engine for Direct Play
        if let router = playerEngineRouter,
           router.lastReport?.preferredBackend == .nativeMediaEngine,
           decision.mode == .directPlay {
            let request = PlaybackRequest(
                metadata: metadata,
                context: context,
                network: network,
                path: .nativeDirectPlay,
                decision: decision,
                mediaURL: url,
                startPositionMs: startMs,
                preferences: effectivePrefs
            )
            do {
                let native = router.nativeBackendInstance()
                try await native.prepare(request: request)
                activePlaybackBackend = .nativeMediaEngine
                router.markActive(.nativeMediaEngine)
                await newSession.updateState(.playing)
                isPlaying = true
                sessionState = .playing
                if nativeSystemBridge == nil {
                    nativeSystemBridge = NativeSystemMediaBridge(
                        nowPlaying: nowPlaying,
                        audioSession: audioSession,
                        logger: logger
                    )
                }
                nativeSystemBridge?.activate(
                    metadata: metadata,
                    artworkURL: artworkURL,
                    durationMs: duration,
                    positionMs: startMs,
                    rate: playbackRate
                )
                startNativeTimelineLoop()
                logger.playback.info("Playing via Native Media Engine")
                return
            } catch {
                logger.playback.info("Native engine failed, falling back to AVPlayer: \(error.localizedDescription)")
                activePlaybackBackend = .avPlayer
                router.markActive(.avPlayer)
            }
        } else {
            activePlaybackBackend = .avPlayer
            playerEngineRouter?.markActive(.avPlayer)
        }

        var assetOptions: [String: Any] = [:]
        var assetHeaders = identityHeaders
        assetHeaders["X-Plex-Token"] = context.token
        assetOptions["AVURLAssetHTTPHeaderFieldsKey"] = assetHeaders
        let asset = AVURLAsset(url: url, options: assetOptions)
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause
        avPlayer.allowsExternalPlayback = true
        avPlayer.usesExternalPlaybackWhileExternalScreenIsActive = true
        self.player = avPlayer

        observe(player: avPlayer, item: item)

        if startMs > 0 {
            let time = CMTime(value: startMs, timescale: 1000)
            await avPlayer.seek(to: time)
        }

        avPlayer.volume = min(1, max(0, volume))
        avPlayer.play()
        applyRateToPlayer()
        isPlaying = true
        sessionState = .playing
        await newSession.updateState(.playing)
        // Apply preferred audio / subtitle once media selection groups are ready.
        let audioId = selectedAudioId
        let subId = selectedSubtitleId
        Task { @MainActor in
            _ = await self.applyAVMediaSelection(audioStreamId: audioId, subtitleStreamId: subId)
        }
        await reportTimeline(force: true)
        startPeriodicReporting()
        publishNowPlaying()
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        applyRateToPlayer()
        logger.playback.info("Playback rate \(rate)x")
    }

    func setAspectMode(_ mode: VideoAspectMode) {
        aspectMode = mode
        // AVPlayer path reacts via PlayerLayerView(aspectMode:); VLC needs an explicit call.
        if activePlaybackBackend == .vlc {
            vlcBackend?.setAspectMode(mode)
        }
    }

    /// Linear volume 0…2 (100% = 1.0, boost up to 200%). VLC maps to 0…200; AVPlayer caps at 1.0.
    private(set) var volume: Float = 1
    static let maxVolume: Float = 2.0

    func setVolume(_ value: Float) {
        let v = min(Self.maxVolume, max(0, value))
        volume = v
        if activePlaybackBackend == .vlc {
            vlcBackend?.setVolume(v)
            return
        }
        // AVPlayer only supports 0…1; boost above 100% requires VLC path.
        player?.volume = min(1, v)
    }

    private func applyRateToPlayer() {
        if activePlaybackBackend == .vlc {
            vlcBackend?.setRate(playbackRate)
            return
        }
        if activePlaybackBackend == .nativeMediaEngine {
            playerEngineRouter?.nativeBackendInstance().setRate(playbackRate)
            return
        }
        guard let player else { return }
        if sessionState == .playing || player.timeControlStatus == .playing {
            player.rate = playbackRate
        } else if playbackRate > 0 {
            player.rate = 0
        }
    }

    func pause() {
        if activePlaybackBackend == .vlc {
            vlcBackend?.pause()
        } else if activePlaybackBackend == .nativeMediaEngine {
            playerEngineRouter?.nativeBackendInstance().pause()
        } else {
            player?.pause()
        }
        isPlaying = false
        sessionState = .paused
        nowPlaying.updateProgress(positionMs: positionMs, durationMs: durationMs, isPlaying: false)
        nativeSystemBridge?.updateProgress(
            positionMs: positionMs, durationMs: durationMs, isPlaying: false, rate: playbackRate
        )
        Task {
            await session?.updateState(.paused)
            await reportTimeline(force: true)
        }
    }

    func resume() {
        if activePlaybackBackend == .vlc {
            vlcBackend?.play()
            applyRateToPlayer()
        } else if activePlaybackBackend == .nativeMediaEngine {
            playerEngineRouter?.nativeBackendInstance().play()
        } else {
            player?.play()
            applyRateToPlayer()
        }
        isPlaying = true
        sessionState = .playing
        nowPlaying.updateProgress(positionMs: positionMs, durationMs: durationMs, isPlaying: true)
        nativeSystemBridge?.updateProgress(
            positionMs: positionMs, durationMs: durationMs, isPlaying: true, rate: playbackRate
        )
        Task {
            await session?.updateState(.playing)
            await reportTimeline(force: true)
        }
    }


    /// IPTV / direct URL playback — no Plex session, timeline, or transcode.
    func playIPTV(
        url: URL,
        headers: [String: String] = [:],
        title: String,
        preferVLC: Bool = true
    ) async {
        await stop(report: false)
        context = nil
        session = nil
        errorMessage = nil
        isPlaying = false
        sessionState = .loading
        currentItem = nil
        decision = nil
        positionMs = 0
        durationMs = 0
        audioStreams = []
        subtitleStreams = []
        selectedAudioId = nil
        selectedSubtitleId = nil
        estimatedThroughputMbps = nil
        throughputSamples = []

        let effectivePrefs = PlaybackSettingsStore.shared.preferences
        playbackRate = effectivePrefs.defaultPlaybackRate
        aspectMode = effectivePrefs.defaultAspectMode

        // Prefer VLC for TS / exotic IPTV; HLS often works on AVPlayer
        let useVLC = preferVLC
            && effectivePrefs.allowVLCPlayer
            && !effectivePrefs.preferSystemPlayer
            && VLCPlaybackBackend.isLinked

        if useVLC {
            do {
                let vlc = vlcBackend ?? VLCPlaybackBackend()
                vlcBackend = vlc
                // Activate backend early so SwiftUI mounts VLCPlayerContainer before play.
                activePlaybackBackend = .vlc
                vlc.onTimeChange = { [weak self] pos, dur in
                    guard let self else { return }
                    self.positionMs = pos
                    if dur > 0 { self.durationMs = dur }
                }
                vlc.onThroughputMbps = { [weak self] mbps in
                    self?.recordThroughputSample(mbps)
                }
                vlc.onEnded = { [weak self] in
                    Task { await self?.handlePlaybackEnded() }
                }
                vlc.onError = { [weak self] message in
                    self?.errorMessage = message
                    self?.sessionState = .error
                    self?.isPlaying = false
                }
                vlc.onStateChange = { [weak self] st in
                    guard let self else { return }
                    switch st {
                    case .playing:
                        self.sessionState = .playing
                        self.isPlaying = true
                    case .paused:
                        self.sessionState = .paused
                        self.isPlaying = false
                    case .buffering:
                        self.sessionState = .buffering
                    case .failed:
                        self.sessionState = .error
                        self.isPlaying = false
                    default:
                        break
                    }
                }
                // Give UI a frame to attach the drawable view.
                try? await Task.sleep(for: .milliseconds(50))
                try await vlc.prepare(
                    url: url,
                    headers: headers,
                    startPositionMs: 0,
                    externalSubtitles: [],
                    preferredSubtitlePlexId: nil,
                    preferredAudioPlexId: nil,
                    forceSoftwareDecode: false
                )
                vlc.rebindDrawable()
                vlc.setVolume(volume)
                vlc.setAspectMode(aspectMode)
                isPlaying = true
                sessionState = .playing
                nowPlaying.updateTitle(title, subtitle: "IPTV")
                logger.playback.info("IPTV via VLC: \(url.absoluteString.prefix(80))")
                return
            } catch {
                logger.playback.error("IPTV VLC failed: \(error.localizedDescription)")
                activePlaybackBackend = .avPlayer
            }
        }

        let asset = AVURLAsset(url: url, options: headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers])
        let item = AVPlayerItem(asset: asset)
        let avPlayer = AVPlayer(playerItem: item)
        avPlayer.actionAtItemEnd = .pause
        self.player = avPlayer
        activePlaybackBackend = .avPlayer
        observe(player: avPlayer, item: item)
        startAccessLogMonitoring(item: item)
        avPlayer.volume = min(1, max(0, volume))
        avPlayer.play()
        isPlaying = true
        sessionState = .playing
        nowPlaying.updateTitle(title, subtitle: "IPTV")
    }

    private func startAccessLogMonitoring(item: AVPlayerItem) {
        if let accessLogObserver {
            NotificationCenter.default.removeObserver(accessLogObserver)
            self.accessLogObserver = nil
        }
        accessLogObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewAccessLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.sampleAccessLog(item: item)
            }
        }
    }

    private func sampleAccessLog(item: AVPlayerItem) {
        guard let log = item.accessLog(), let event = log.events.last else { return }
        // observedBitrate is bits/s
        let bps = event.observedBitrate
        guard bps > 0 else { return }
        recordThroughputSample(bps / 1_000_000)
    }

    private func recordThroughputSample(_ mbps: Double) {
        guard mbps > 0.05, mbps < 500 else { return }
        throughputSamples.append(mbps)
        if throughputSamples.count > 12 {
            throughputSamples.removeFirst(throughputSamples.count - 12)
        }
        estimatedThroughputMbps = throughputSamples.reduce(0, +) / Double(throughputSamples.count)
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func seek(toMs ms: Int64) async {
        if activePlaybackBackend == .vlc {
            await vlcBackend?.seek(toMs: ms)
        } else if activePlaybackBackend == .nativeMediaEngine {
            await playerEngineRouter?.nativeBackendInstance().seek(toMs: ms)
        } else {
            let time = CMTime(value: ms, timescale: 1000)
            await player?.seek(to: time)
        }
        positionMs = ms
        await session?.updatePosition(ms)
        nowPlaying.updateProgress(positionMs: positionMs, durationMs: durationMs, isPlaying: isPlaying)
        nativeSystemBridge?.updateProgress(
            positionMs: positionMs, durationMs: durationMs, isPlaying: isPlaying, rate: playbackRate
        )
        await reportTimeline(force: true)
    }

    func skip(seconds: Int64) async {
        let target = max(0, min(durationMs, positionMs + seconds * 1000))
        await seek(toMs: target)
    }

    func stop(report: Bool = true, notifyLibraryProgress: Bool = true) async {
        reportTask?.cancel()
        reportTask = nil
        nativeTimelineTask?.cancel()
        nativeTimelineTask = nil
        if activePlaybackBackend == .vlc {
            await vlcBackend?.stop()
        }
        if activePlaybackBackend == .nativeMediaEngine {
            await playerEngineRouter?.nativeBackendInstance().stop()
            nativeSystemBridge?.deactivate()
        }
        activePlaybackBackend = .avPlayer
        removeObservers()

        if report, session != nil, context != nil {
            await session?.updateState(.stopped)
            await reportTimeline(force: true)
            if notifyLibraryProgress {
                LibraryProgressEvents.postProgressDidChange(machineIdentifier: context?.machineIdentifier)
            }
        }

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        session = nil
        isPlaying = false
        sessionState = .idle
        currentItem = nil
        decision = nil
        positionMs = 0
        durationMs = 0
        artworkURL = nil
        nowPlaying.clear()
        audioSession.deactivate()
    }

    func selectAudio(streamId: Int) async {
        selectedAudioId = streamId
        guard let metadata = currentItem, let context else { return }

        if activePlaybackBackend == .vlc {
            // Live currentAudioTrackIndex hard-crashes MobileVLCKit (device logs).
            // Soft-restart with forced preference and restore position.
            let label = audioStreams.first { $0.id == streamId }
                .map { "\($0.displayTitle ?? $0.language ?? $0.codec ?? "?") id=\($0.id)" }
                ?? "id=\(streamId)"
            logger.playback.info("selectAudio VLC soft-restart → \(label)")
            FileLogStore.shared.flush()
            let resumeFrom = positionMs
            await play(
                metadata: metadata,
                context: context,
                network: networkClass,
                resume: false,
                forcedAudioId: streamId,
                forcedSubtitleId: selectedSubtitleId
            )
            if resumeFrom > 0 {
                try? await Task.sleep(for: .milliseconds(500))
                await seek(toMs: resumeFrom)
            }
            return
        }

        // Prefer in-player media selection when Direct Play (no server round-trip)
        if decision?.mode == .directPlay,
           await applyAVMediaSelection(audioStreamId: streamId, subtitleStreamId: selectedSubtitleId) {
            return
        }

        let resumeFrom = positionMs
        await play(
            metadata: metadata,
            context: context,
            network: networkClass,
            resume: false,
            forcedAudioId: streamId,
            forcedSubtitleId: selectedSubtitleId
        )
        if resumeFrom > 0 {
            await seek(toMs: resumeFrom)
        }
    }

    func selectSubtitle(streamId: Int?) async {
        selectedSubtitleId = streamId
        guard let metadata = currentItem, let context else { return }

        if activePlaybackBackend == .vlc {
            // Same as audio — never mutate live subtitle index on MobileVLCKit.
            let label = streamId.flatMap { id in subtitleStreams.first { $0.id == id } }
                .map { "\($0.displayTitle ?? $0.language ?? $0.codec ?? "?") id=\($0.id) ext=\($0.isExternal)" }
                ?? "off"
            logger.playback.info("selectSubtitle VLC soft-restart → \(label)")
            FileLogStore.shared.flush()
            let resumeFrom = positionMs
            await play(
                metadata: metadata,
                context: context,
                network: networkClass,
                resume: false,
                forcedAudioId: selectedAudioId,
                forcedSubtitleId: streamId ?? -1
            )
            if resumeFrom > 0 {
                try? await Task.sleep(for: .milliseconds(500))
                await seek(toMs: resumeFrom)
            }
            return
        }

        if decision?.mode == .directPlay,
           await applyAVMediaSelection(audioStreamId: selectedAudioId, subtitleStreamId: streamId) {
            return
        }

        let resumeFrom = positionMs
        await play(
            metadata: metadata,
            context: context,
            network: networkClass,
            resume: false,
            forcedAudioId: selectedAudioId,
            forcedSubtitleId: streamId ?? -1
        )
        if resumeFrom > 0 {
            await seek(toMs: resumeFrom)
        }
    }

    // MARK: - VLC audio / subtitles

    private func applyVLCAudioSelection(_ streamId: Int?) {
        guard let vlc = vlcBackend, let streamId else { return }
        let stream = audioStreams.first { $0.id == streamId }
        vlc.applyPlexAudio(stream: stream, allAudioStreams: audioStreams)
    }

    private func applyVLCSubtitleSelection(_ streamId: Int?, context: ServerContext) {
        guard let vlc = vlcBackend else { return }
        let stream = streamId.flatMap { id in subtitleStreams.first { $0.id == id } }
        vlc.applyPlexSubtitle(stream: stream, allSubtitleStreams: subtitleStreams) { s in
            Self.externalSubtitleURL(stream: s, baseURL: context.baseURL, token: context.token)
        }
    }

    /// True only for Plex *file* sidecars. Embedded SRT/ASS inside MKV/MP4 must
    /// stay false — they are selected via VLC `sub-track`, not sub-file download.
    static func isSidecarSubtitle(_ stream: PlexStream) -> Bool {
        guard stream.streamType == .subtitle else { return false }
        // Explicit external flag from PMS
        if stream.isExternal { return true }
        // Plex external stream endpoint (sidecar file on disk)
        if let key = stream.key, key.contains("/library/streams/") {
            return true
        }
        return false
    }

    private static func externalSubtitleURLs(streams: [PlexStream], baseURL: URL, token: String) -> [URL] {
        streams.filter(isSidecarSubtitle).compactMap { externalSubtitleURL(stream: $0, baseURL: baseURL, token: token) }
    }

    private static func externalSubtitleURL(stream: PlexStream, baseURL: URL, token: String) -> URL? {
        // Prefer explicit key; fallback to /library/streams/{id} (Plex standard for external).
        let key: String
        if let k = stream.key, !k.isEmpty {
            key = k
        } else {
            key = "/library/streams/" + String(stream.id)
        }
        if key.hasPrefix("http://") || key.hasPrefix("https://") {
            var c = URLComponents(string: key)
            var items = c?.queryItems ?? []
            if items.contains(where: { $0.name == "X-Plex-Token" }) != true {
                items.append(URLQueryItem(name: "X-Plex-Token", value: token))
            }
            c?.queryItems = items
            return c?.url
        }
        let path = key.hasPrefix("/") ? String(key.dropFirst()) : key
        return PlexURL.join(baseURL, path: path, query: [
            URLQueryItem(name: "X-Plex-Token", value: token)
        ])
    }

    /// Select audio/subtitle options on the current AVPlayerItem.
    /// Retries briefly — HLS often exposes legible groups only after the playlist loads.
    /// Match AVMediaSelectionOption to a Plex stream language / title (with aliases).
    private static func matchAVOption(
        options: [AVMediaSelectionOption],
        languageCode: String?,
        languageName: String?,
        title: String?
    ) -> AVMediaSelectionOption? {
        let needles = languageNeedles(code: languageCode, name: languageName)
        let titleL = (title ?? "").lowercased()

        if let exact = options.first(where: { opt in
            let code = opt.locale?.language.languageCode?.identifier.lowercased() ?? ""
            let display = opt.displayName.lowercased()
            if needles.contains(where: { code == $0 || code.hasPrefix($0) || $0.hasPrefix(code) }) {
                return true
            }
            if needles.contains(where: { display.contains($0) }) { return true }
            return false
        }) {
            return exact
        }
        if !titleL.isEmpty {
            return options.first { $0.displayName.lowercased().contains(titleL) }
        }
        return nil
    }

    private static func languageNeedles(code: String?, name: String?) -> [String] {
        var set = Set<String>()
        for raw in [code, name].compactMap({ $0?.lowercased() }) where !raw.isEmpty {
            set.insert(raw)
            let base = String(raw.prefix(while: { $0.isLetter }))
            if !base.isEmpty { set.insert(base) }
            let aliases: [String: [String]] = [
                "zh": ["chi", "zho", "zh-cn", "zh-tw", "zh-hans", "zh-hant", "chinese", "cmn", "yue"],
                "en": ["eng", "english"],
                "ja": ["jpn", "japanese"],
                "ko": ["kor", "korean"],
                "es": ["spa", "spanish"],
                "fr": ["fre", "fra", "french"],
                "de": ["ger", "deu", "german"],
                "pt": ["por", "portuguese"],
                "ru": ["rus", "russian"],
            ]
            if let list = aliases[base] {
                list.forEach { set.insert($0) }
            }
            for (k, list) in aliases where list.contains(raw) || list.contains(base) {
                set.insert(k)
                list.forEach { set.insert($0) }
            }
        }
        return Array(set)
    }

    private func applyAVMediaSelection(audioStreamId: Int?, subtitleStreamId: Int?) async -> Bool {
        for attempt in 0..<5 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(400))
            }
            if await applyAVMediaSelectionOnce(audioStreamId: audioStreamId, subtitleStreamId: subtitleStreamId) {
                return true
            }
        }
        return false
    }

    private func applyAVMediaSelectionOnce(audioStreamId: Int?, subtitleStreamId: Int?) async -> Bool {
        guard let item = player?.currentItem else { return false }
        do {
            let asset = item.asset
            let characteristics = try await asset.load(.availableMediaCharacteristicsWithMediaSelectionOptions)
            var applied = false

            if let audioStreamId,
               characteristics.contains(.audible),
               let group = try await asset.loadMediaSelectionGroup(for: .audible) {
                let options = group.options
                if let stream = audioStreams.first(where: { $0.id == audioStreamId }) {
                    let match = Self.matchAVOption(
                        options: options,
                        languageCode: stream.languageCode,
                        languageName: stream.language,
                        title: stream.displayTitle ?? stream.title
                    )
                    if let match {
                        item.select(match, in: group)
                        applied = true
                        logger.playback.info("Audio legible option: \(match.displayName)")
                    }
                }
            }

            if characteristics.contains(.legible),
               let group = try await asset.loadMediaSelectionGroup(for: .legible) {
                if subtitleStreamId != nil {
                    let stream = subtitleStreams.first(where: { $0.id == subtitleStreamId })
                    let candidates = group.options.filter { !$0.displayName.lowercased().contains("disabled") }
                    let pool = candidates.isEmpty ? group.options : candidates
                    let match = Self.matchAVOption(
                        options: pool,
                        languageCode: stream?.languageCode,
                        languageName: stream?.language,
                        title: stream?.displayTitle ?? stream?.title
                    ) ?? pool.first
                    if let match {
                        item.select(match, in: group)
                        applied = true
                        logger.playback.info("Subtitle legible option: \(match.displayName)")
                    }
                } else {
                    item.select(nil, in: group)
                    applied = true
                }
            } else if subtitleStreamId != nil {
                // Legible group not ready yet
                return false
            }

            return applied
        } catch {
            logger.playback.debug("AVMediaSelection failed: \(error.localizedDescription)")
            return false
        }
    }

    func markWatched() async {
        guard let context, let item = currentItem else { return }
        await timelineReporter.scrobble(baseURL: context.baseURL, token: context.token, key: item.key)
    }

    func markUnwatched() async {
        guard let context, let item = currentItem else { return }
        await timelineReporter.unscrobble(baseURL: context.baseURL, token: context.token, key: item.key)
    }

    /// Scrobble/unscrobble for a metadata item that is not necessarily the active player item.
    func setWatched(_ watched: Bool, item: PlexMetadata, context: ServerContext) async {
        if watched {
            await timelineReporter.scrobble(baseURL: context.baseURL, token: context.token, key: item.key)
        } else {
            await timelineReporter.unscrobble(baseURL: context.baseURL, token: context.token, key: item.key)
        }
        LibraryProgressEvents.postProgressDidChange(machineIdentifier: context.machineIdentifier)
    }

    func refreshNowPlaying() {
        publishNowPlaying()
    }

    // MARK: - Internals

    
    private func startNativeTimelineLoop() {
        nativeTimelineTask?.cancel()
        nativeTimelineTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let pos: Int64 = await MainActor.run {
                    let p = self.playerEngineRouter?.nativeBackendInstance().positionMs ?? self.positionMs
                    self.positionMs = p
                    self.nativeSystemBridge?.updateProgress(
                        positionMs: p,
                        durationMs: self.durationMs,
                        isPlaying: self.sessionState == .playing,
                        rate: self.playbackRate
                    )
                    return p
                }
                if let context = await MainActor.run(body: { self.context }),
                   let session = await MainActor.run(body: { self.session }) {
                    await session.updatePosition(pos)
                    await session.updateState(.playing)
                    await self.timelineReporter.report(
                        baseURL: context.baseURL,
                        token: context.token,
                        clientIdentifier: self.clientIdentifier,
                        session: session,
                        continuing: true
                    )
                }
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        sessionState = .error
        logger.playback.error("\(message)")
    }

    private func observe(player: AVPlayer, item: AVPlayerItem) {
        removeObservers()

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let ms = Int64(CMTimeGetSeconds(time) * 1000)
            self.positionMs = max(0, ms)
            Task { await self.session?.updatePosition(ms) }
            // Throttle Now Playing progress updates
            if Int(ms / 1000) % 2 == 0 {
                self.nowPlaying.updateProgress(
                    positionMs: self.positionMs,
                    durationMs: self.durationMs,
                    isPlaying: self.isPlaying
                )
            }
        }

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch item.status {
                case .readyToPlay:
                    if self.sessionState == .loading {
                        self.isPlaying = true
                        self.sessionState = .playing
                    }
                    // Apply preferred audio/subtitle once tracks are available
                    Task {
                        _ = await self.applyAVMediaSelection(
                            audioStreamId: self.selectedAudioId,
                            subtitleStreamId: self.selectedSubtitleId
                        )
                        self.applyRateToPlayer()
                    }
                case .failed:
                    self.fail(item.error?.localizedDescription ?? "Player item failed")
                default:
                    break
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch player.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    self.isBuffering = true
                    if self.sessionState == .playing {
                        self.sessionState = .buffering
                        Task { await self.session?.updateState(.buffering) }
                    }
                case .playing:
                    self.isBuffering = false
                    self.isPlaying = true
                    self.sessionState = .playing
                case .paused:
                    self.isBuffering = false
                    // Do not clear isPlaying — user pause()/resume() owns that for UI.
                @unknown default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handlePlaybackEnded()
            }
        }
    }

    private func removeObservers() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        statusObservation = nil
        timeControlObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        if let accessLogObserver {
            NotificationCenter.default.removeObserver(accessLogObserver)
        }
        accessLogObserver = nil
    }

    private func handlePlaybackEnded() async {
        isPlaying = false
        sessionState = .stopped
        await session?.updateState(.stopped)
        await reportTimeline(force: true)
        if let context, let item = currentItem {
            await timelineReporter.scrobble(
                baseURL: context.baseURL,
                token: context.token,
                key: item.key
            )
            LibraryProgressEvents.postProgressDidChange(machineIdentifier: context.machineIdentifier)
        }
        nowPlaying.updateProgress(positionMs: durationMs, durationMs: durationMs, isPlaying: false)

        // Auto-play next episode when preferences allow
        await tryAutoplayNextEpisode()
    }

    private func tryAutoplayNextEpisode() async {
        guard PlaybackSettingsStore.shared.preferences.autoPlayNextEpisode else { return }
        guard let context, let item = currentItem, item.type == .episode else { return }

        do {
            guard var next = try await resolveNextEpisode(from: item, context: context) else {
                logger.playback.info("Autoplay: no next episode")
                return
            }
            // Ensure media/parts present for decision engine
            if next.media.isEmpty {
                next = try await fetchFullMetadata(ratingKey: next.ratingKey, context: context)
            }
            logger.playback.info("Autoplay next: \(next.title) (\(next.ratingKey))")
            await play(metadata: next, context: context, network: networkClass, resume: false)
        } catch {
            logger.playback.error("Autoplay failed: \(error.localizedDescription)")
        }
    }

    /// Resolves the next episode, including across season boundaries.
    /// Order: related hubs → same-season next → next season's first episode.
    /// When parent/grandparent keys are missing on the playback item, re-fetch full metadata.
    private func resolveNextEpisode(from item: PlexMetadata, context: ServerContext) async throws -> PlexMetadata? {
        var episode = item
        if episode.parentRatingKey == nil || episode.grandparentRatingKey == nil {
            if let full = try? await fetchFullMetadata(ratingKey: item.ratingKey, context: context) {
                episode = full
            }
        }

        // 1) Server-provided related / up-next
        if let fromHub = try? await nextFromRelatedHubs(ratingKey: episode.ratingKey, context: context) {
            return fromHub
        }

        let parentKey = episode.parentRatingKey
        let showKey = episode.grandparentRatingKey

        // 2) Same season: next by index or list order
        if let parentKey {
            let siblings = try await fetchChildrenMetadata(ratingKey: parentKey, context: context)
                .filter { $0.type == .episode || $0.type == .unknown }
                .sorted { ($0.index ?? 0) < ($1.index ?? 0) }

            if let idx = episode.index,
               let next = siblings.first(where: { ($0.index ?? -1) == idx + 1 }) {
                return next
            }
            if let pos = siblings.firstIndex(where: { $0.ratingKey == episode.ratingKey }),
               pos + 1 < siblings.count {
                return siblings[pos + 1]
            }

            // 3) End of season → next season's first episode (cross-season)
            let resolvedShowKey = showKey
                ?? siblings.first(where: { $0.grandparentRatingKey != nil })?.grandparentRatingKey
            if let resolvedShowKey {
                if let cross = try await firstEpisodeOfNextSeason(
                    showKey: resolvedShowKey,
                    currentSeasonKey: parentKey,
                    currentSeasonIndex: episode.parentIndex,
                    context: context
                ) {
                    return cross
                }
            }
        }

        // 4) No parentRatingKey: try grandparent seasons only
        if let showKey {
            return try await firstEpisodeOfNextSeason(
                showKey: showKey,
                currentSeasonKey: parentKey,
                currentSeasonIndex: episode.parentIndex,
                context: context
            )
        }

        // 5) Last resort: related hubs without title filter (any hub with episode after current)
        if let anyHub = try? await fetchRelatedHubs(ratingKey: episode.ratingKey, context: context) {
            for hub in anyHub {
                if let next = hub.items.first(where: {
                    $0.type == .episode && $0.ratingKey != episode.ratingKey
                }) {
                    return next
                }
            }
        }

        return nil
    }

    private func nextFromRelatedHubs(ratingKey: String, context: ServerContext) async throws -> PlexMetadata? {
        let related = try await fetchRelatedHubs(ratingKey: ratingKey, context: context)
        for hub in related {
            let id = (hub.hubIdentifier ?? hub.key).lowercased()
            let title = hub.title.lowercased()
            if id.contains("continue") || id.contains("next")
                || title.contains("up next") || title.contains("next episode") {
                if let first = hub.items.first(where: { $0.type == .episode || $0.type == .unknown }) {
                    return first
                }
                if let first = hub.items.first { return first }
            }
        }
        return nil
    }

    private func firstEpisodeOfNextSeason(
        showKey: String,
        currentSeasonKey: String?,
        currentSeasonIndex: Int?,
        context: ServerContext
    ) async throws -> PlexMetadata? {
        let seasons = try await fetchChildrenMetadata(ratingKey: showKey, context: context)
            .filter { $0.type == .season || $0.type == .unknown }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }

        guard !seasons.isEmpty else { return nil }

        let nextSeason: PlexMetadata?
        if let currentSeasonKey,
           let pos = seasons.firstIndex(where: { $0.ratingKey == currentSeasonKey }),
           pos + 1 < seasons.count {
            nextSeason = seasons[pos + 1]
        } else if let currentSeasonIndex,
                  let match = seasons.first(where: { ($0.index ?? -1) == currentSeasonIndex + 1 }) {
            nextSeason = match
        } else {
            nextSeason = nil
        }

        guard let nextSeason else { return nil }

        let episodes = try await fetchChildrenMetadata(ratingKey: nextSeason.ratingKey, context: context)
            .filter { $0.type == .episode || $0.type == .unknown }
            .sorted { ($0.index ?? 0) < ($1.index ?? 0) }

        return episodes.first
    }

    private func fetchFullMetadata(ratingKey: String, context: ServerContext) async throws -> PlexMetadata {
        guard let url = PlexURL.join(context.baseURL, path: "library/metadata/\(ratingKey)") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(context.token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await http.data(for: request, allowNon2xx: false, retryCount: 1)
        let decoded = try JSONDecoder().decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        guard let item = (decoded.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:)).first else {
            throw PlexError.mediaUnavailable
        }
        return item
    }

    private func fetchRelatedHubs(ratingKey: String, context: ServerContext) async throws -> [PlexHub] {
        guard let url = PlexURL.join(context.baseURL, path: "hubs/metadata/\(ratingKey)/related") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(context.token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await http.data(for: request, allowNon2xx: false, retryCount: 1)
        let decoded = try JSONDecoder().decode(APIMediaContainer<APIHubsContainer>.self, from: response.data)
        return (decoded.mediaContainer.hub ?? []).compactMap(PlexAPIMapper.hub(from:))
    }

    private func fetchChildrenMetadata(ratingKey: String, context: ServerContext) async throws -> [PlexMetadata] {
        guard let url = PlexURL.join(context.baseURL, path: "library/metadata/\(ratingKey)/children") else {
            throw PlexError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.setValue(context.token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await http.data(for: request, allowNon2xx: false, retryCount: 1)
        let decoded = try JSONDecoder().decode(APIMediaContainer<APIMetadataContainer>.self, from: response.data)
        return (decoded.mediaContainer.metadata ?? []).compactMap(PlexAPIMapper.metadata(from:))
    }

    private func startPeriodicReporting() {
        reportTask?.cancel()
        reportTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.reportTimeline(force: false)
            }
        }
    }

    private func reportTimeline(force: Bool) async {
        guard let session, let context else { return }
        let should: Bool
        if force {
            should = true
        } else {
            should = await session.shouldReport(force: false)
        }
        guard should else { return }
        await timelineReporter.report(
            baseURL: context.baseURL,
            token: context.token,
            clientIdentifier: clientIdentifier,
            session: session
        )
    }

    private func publishNowPlaying() {
        guard let metadata = currentItem else { return }
        nowPlaying.update(
            metadata: metadata,
            positionMs: positionMs,
            durationMs: durationMs,
            isPlaying: isPlaying,
            artworkURL: artworkURL
        )
    }
}

// MARK: - Safe subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
