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

    var isPlaying: Bool { sessionState == .playing }

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
        await stop(report: true)

        self.context = context
        self.networkClass = network
        self.currentItem = metadata
        self.errorMessage = nil
        sessionState = .loading

        // Always use persisted user defaults for decision + start rate/aspect
        let effectivePrefs = PlaybackSettingsStore.shared.preferences
        playbackRate = effectivePrefs.defaultPlaybackRate
        aspectMode = effectivePrefs.defaultAspectMode

        let engine = PlaybackDecisionEngine(
            capabilities: .current,
            preferences: effectivePrefs
        )
        let decision = engine.decide(
            metadata: metadata,
            network: network,
            forcedAudioId: forcedAudioId,
            forcedSubtitleId: forcedSubtitleId
        )
        self.decision = decision
        logger.playback.info("Decision: \(decision.mode.rawValue) — \(decision.reason)")
        if let router = playerEngineRouter {
            let report = router.resolve(metadata: metadata, decision: decision, network: network)
            var probe = MediaProbe().probeFromPlexMetadata(
                metadata,
                mediaIndex: decision.mediaIndex,
                partIndex: decision.partIndex
            )
            // Phase 2: best-effort HTTP Range container probe (does not block path choice)
            if let enriched = await MediaProbe().probePlexPart(
                    metadata: metadata,
                    context: context,
                    mediaIndex: decision.mediaIndex,
                    partIndex: decision.partIndex
                ) {
                    probe = enriched
                }
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
            logger.playback.error("Audio session: \(error.localizedDescription)")
        }

        artworkURL = PlexImageURL.resolve(
            path: metadata.thumb ?? metadata.art,
            baseURL: context.baseURL,
            token: context.token,
            width: 600,
            height: 900
        )

        let asset = AVURLAsset(url: url)
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

        avPlayer.play()
        applyRateToPlayer()
        sessionState = .playing
        await newSession.updateState(.playing)
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
    }

    private func applyRateToPlayer() {
        guard let player else { return }
        if sessionState == .playing || player.timeControlStatus == .playing {
            player.rate = playbackRate
        } else if playbackRate > 0 {
            // Keep preferred rate for next resume
            player.rate = 0
        }
    }

    func pause() {
        player?.pause()
        sessionState = .paused
        nowPlaying.updateProgress(positionMs: positionMs, durationMs: durationMs, isPlaying: false)
        Task {
            await session?.updateState(.paused)
            await reportTimeline(force: true)
        }
    }

    func resume() {
        player?.play()
        applyRateToPlayer()
        sessionState = .playing
        nowPlaying.updateProgress(positionMs: positionMs, durationMs: durationMs, isPlaying: true)
        Task {
            await session?.updateState(.playing)
            await reportTimeline(force: true)
        }
    }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func seek(toMs ms: Int64) async {
        let time = CMTime(value: ms, timescale: 1000)
        await player?.seek(to: time)
        positionMs = ms
        await session?.updatePosition(ms)
        nowPlaying.updateProgress(positionMs: positionMs, durationMs: durationMs, isPlaying: isPlaying)
        await reportTimeline(force: true)
    }

    func skip(seconds: Int64) async {
        let target = max(0, min(durationMs, positionMs + seconds * 1000))
        await seek(toMs: target)
    }

    func stop(report: Bool = true) async {
        reportTask?.cancel()
        reportTask = nil
        removeObservers()

        if report, session != nil, context != nil {
            await session?.updateState(.stopped)
            await reportTimeline(force: true)
        }

        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        session = nil
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

    /// Select audio/subtitle options on the current AVPlayerItem.
    /// Retries briefly — HLS often exposes legible groups only after the playlist loads.
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
                    let lang = stream.languageCode ?? stream.language
                    let title = (stream.displayTitle ?? "").lowercased()
                    let match = options.first(where: { opt in
                        if let lang, let code = opt.locale?.language.languageCode?.identifier {
                            if code.lowercased() == lang.lowercased() { return true }
                        }
                        if !title.isEmpty, opt.displayName.lowercased().contains(title) { return true }
                        return false
                    }) ?? options.first
                    if let match {
                        item.select(match, in: group)
                        applied = true
                    }
                }
            }

            if characteristics.contains(.legible),
               let group = try await asset.loadMediaSelectionGroup(for: .legible) {
                if subtitleStreamId != nil {
                    let stream = subtitleStreams.first(where: { $0.id == subtitleStreamId })
                    let lang = (stream?.languageCode ?? stream?.language)?.lowercased()
                    let title = (stream?.displayTitle ?? stream?.title ?? "").lowercased()
                    // Skip forced-only / "disabled" options when possible
                    let candidates = group.options.filter { !$0.displayName.lowercased().contains("disabled") }
                    let pool = candidates.isEmpty ? group.options : candidates
                    let match = pool.first(where: { opt in
                        if let lang, let code = opt.locale?.language.languageCode?.identifier {
                            if code.lowercased() == lang { return true }
                        }
                        if !title.isEmpty, opt.displayName.lowercased().contains(title) { return true }
                        return false
                    }) ?? pool.first
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
    }

    func refreshNowPlaying() {
        publishNowPlaying()
    }

    // MARK: - Internals

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
                    self.sessionState = .playing
                case .paused:
                    self.isBuffering = false
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
    }

    private func handlePlaybackEnded() async {
        sessionState = .stopped
        await session?.updateState(.stopped)
        await reportTimeline(force: true)
        if let context, let item = currentItem {
            await timelineReporter.scrobble(
                baseURL: context.baseURL,
                token: context.token,
                key: item.key
            )
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
