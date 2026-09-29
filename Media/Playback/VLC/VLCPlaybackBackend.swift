import Foundation
import UIKit

#if canImport(VLCKitSPM)
import VLCKitSPM
private enum VLCKitImport { static let available = true }
#elseif canImport(MobileVLCKit)
import MobileVLCKit
private enum VLCKitImport { static let available = true }
#else
private enum VLCKitImport { static let available = false }
#endif

/// MobileVLCKit Direct Play backend. Keeps drawable + track state for PlayerView.
@MainActor
final class VLCPlaybackBackend: NSObject {
    nonisolated static var isLinked: Bool { VLCKitImport.available }

    let backendKind: PlaybackBackend = .vlc
    private(set) var state: MediaEngineSessionState = .idle
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var rate: Float = 1.0

    private(set) var drawableView: UIView = {
        let v = UIView()
        v.backgroundColor = .black
        v.isUserInteractionEnabled = false
        return v
    }()

    private(set) var audioTracks: [(index: Int, name: String)] = []
    private(set) var subtitleTracks: [(index: Int, name: String)] = []
    private(set) var selectedAudioIndex: Int = -1
    private(set) var selectedSubtitleIndex: Int = -1

    var onStateChange: ((MediaEngineSessionState) -> Void)?
    var onTimeChange: ((Int64, Int64) -> Void)?
    var onEnded: (() -> Void)?
    var onError: ((String) -> Void)?
    /// Fired after track lists refresh (UI can rebind menus).
    var onTracksUpdated: (() -> Void)?
    /// Estimated throughput in Mbps (from VLC media stats when available).
    var onThroughputMbps: ((Double) -> Void)?
    private(set) var estimatedThroughputMbps: Double?
    private var throughputSamples: [Double] = []

    /// Last requested aspect mode (re-applied after rebind / when video size is known).
    private(set) var aspectMode: VideoAspectMode = .fit

    /// Call after rotation / container layout so VLC uses non-zero landscape bounds.
    func rebindDrawable() {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        drawableView.setNeedsLayout()
        drawableView.layoutIfNeeded()
        mediaPlayer.drawable = nil
        mediaPlayer.drawable = drawableView
        applyAspectMode(aspectMode)
#endif
    }

    /// Fit / fill / stretch. VLC ignores UIView.contentMode — use crop + aspect ratio APIs.
    func setAspectMode(_ mode: VideoAspectMode) {
        aspectMode = mode
        applyAspectMode(mode)
    }

    private func applyAspectMode(_ mode: VideoAspectMode) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        drawableView.setNeedsLayout()
        drawableView.layoutIfNeeded()

        mediaPlayer.scaleFactor = 0
        // MobileVLCKit ObjC setters free previous + strdup input — pass transient C strings only.
        applyVLCStringProperty(nil, to: mediaPlayer, crop: true)
        applyVLCStringProperty(nil, to: mediaPlayer, crop: false)

        let viewSize = drawableView.bounds.size
        let videoSize = mediaPlayer.videoSize
        let hasVideo = videoSize.width > 1 && videoSize.height > 1
        let hasView = viewSize.width > 1 && viewSize.height > 1

        switch mode {
        case .fit:
            break
        case .stretch:
            if hasView {
                let w = max(1, Int(viewSize.width.rounded()))
                let h = max(1, Int(viewSize.height.rounded()))
                applyVLCStringProperty("\(w):\(h)", to: mediaPlayer, crop: false)
            }
        case .fill:
            if hasVideo, hasView {
                let vW = CGFloat(videoSize.width)
                let vH = CGFloat(videoSize.height)
                let viewAspect = viewSize.width / viewSize.height
                let videoAspect = vW / vH
                if viewAspect > videoAspect {
                    let newH = vW / viewAspect
                    let y = max(0, (vH - newH) / 2)
                    applyVLCStringProperty(
                        "0+\(Int(y.rounded()))+\(Int(vW.rounded()))x\(Int(newH.rounded()))",
                        to: mediaPlayer,
                        crop: true
                    )
                } else {
                    let newW = vH * viewAspect
                    let x = max(0, (vW - newW) / 2)
                    applyVLCStringProperty(
                        "\(Int(x.rounded()))+0+\(Int(newW.rounded()))x\(Int(vH.rounded()))",
                        to: mediaPlayer,
                        crop: true
                    )
                }
            } else if hasView {
                let w = max(1, Int(viewSize.width.rounded()))
                let h = max(1, Int(viewSize.height.rounded()))
                applyVLCStringProperty("\(w):\(h)", to: mediaPlayer, crop: false)
            }
        }
#endif
    }

#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
    /// Setter copies the C string; do not strdup on the caller side (avoids leaks / double-free).
    private func applyVLCStringProperty(_ value: String?, to player: VLCMediaPlayer, crop: Bool) {
        if let value {
            value.withCString { cStr in
                let ptr = UnsafeMutablePointer(mutating: cStr)
                if crop {
                    player.videoCropGeometry = ptr
                } else {
                    player.videoAspectRatio = ptr
                }
            }
        } else if crop {
            player.videoCropGeometry = nil
        } else {
            player.videoAspectRatio = nil
        }
    }

    private var mediaPlayer: VLCMediaPlayer?
#endif

    private var timeTimer: Timer?
    private var pendingSubtitlePlexId: Int?
    private var pendingSubtitleStream: PlexStream?
    private var pendingSubtitleAll: [PlexStream] = []
    private var pendingSubtitleResolve: ((PlexStream) -> URL?)?
    private var pendingEnforceExternal = false
    private var attachedExternalFileURLs: [URL] = []
    private var pendingAudioPlexId: Int?
    private var pendingAudioStream: PlexStream?
    private var pendingAudioAll: [PlexStream] = []
    private var trackApplyTask: Task<Void, Never>?
    private var externalSubtitleURLs: [URL] = []
    private var httpHeaders: [String: String] = [:]

    /// - Parameters:
    ///   - externalSubtitles: Plex external subtitle file URLs (with token if needed).
    ///   - preferredSubtitlePlexId: Plex stream id to enable once tracks appear.
    ///   - preferredAudioPlexId: Plex audio stream id to enable once tracks appear.
    func prepare(
        url: URL,
        headers: [String: String],
        startPositionMs: Int64,
        externalSubtitles: [URL] = [],
        preferredSubtitlePlexId: Int? = nil,
        preferredAudioPlexId: Int? = nil,
        forceSoftwareDecode: Bool = false
    ) async throws {
        guard VLCKitImport.available else {
            throw PlaybackFailure(stage: .unknown, reason: "MobileVLCKit not linked", underlying: nil)
        }
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        stopInternal()
        state = .loading
        onStateChange?(.loading)
        httpHeaders = headers
        externalSubtitleURLs = externalSubtitles
        pendingSubtitlePlexId = preferredSubtitlePlexId
        pendingAudioPlexId = preferredAudioPlexId

        let player = VLCMediaPlayer()
        player.delegate = self
        player.drawable = drawableView

        let media = VLCMedia(url: url)
        var opts: [String: Any] = [
            "network-caching": 1500,
            "http-reconnect": true,
            "sub-fps": 25,
            "freetype-rel-fontsize": 16
        ]
        // VP9 / problematic HW paths: disable hardware decode to avoid green/artifact frames.
        if forceSoftwareDecode {
            opts["avcodec-hw"] = "none"
            opts["no-videotoolbox"] = true
        }
        if !headers.isEmpty {
            let headerLines = headers.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
            opts["http-headers"] = headerLines
        }
        media.addOptions(opts)
        player.media = media
        self.mediaPlayer = player

        player.play()

        // Download external sidecars to temp files then attach — remote HTTP slaves
        // often fail without the same session headers VLC uses for the media URL.
        let enforceFirst = preferredSubtitlePlexId != nil
        Task { @MainActor in
            for (i, subURL) in externalSubtitles.enumerated() {
                await self.attachExternalSubtitle(url: subURL, enforce: enforceFirst && i == 0)
            }
            self.refreshTracks()
            if preferredSubtitlePlexId != nil, let last = self.subtitleTracks.last {
                self.selectSubtitleIndex(last.index)
            }
        }

        if startPositionMs > 0 {
            player.time = VLCTime(int: Int32(clamping: startPositionMs))
        }

        startTimePolling()
        rate = 1.0
        state = .playing
        onStateChange?(.playing)

        // Tracks often appear slightly after play starts.
        scheduleTrackRefreshAndApply()
#else
        throw PlaybackFailure(stage: .unknown, reason: "MobileVLCKit not linked", underlying: nil)
#endif
    }

    func play() {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        mediaPlayer?.play()
        state = .playing
        onStateChange?(.playing)
#endif
    }

    func pause() {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        mediaPlayer?.pause()
        state = .paused
        onStateChange?(.paused)
#endif
    }

    func stop() async {
        stopInternal()
        state = .stopped
        onStateChange?(.stopped)
    }

    func seek(toMs ms: Int64) async {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        mediaPlayer.time = VLCTime(int: Int32(clamping: ms))
        positionMs = ms
        onTimeChange?(positionMs, durationMs)
#endif
    }

    func setVolume(_ linear: Float) {
        // VLC uses 0…100
        let v = Int(min(1, max(0, linear)) * 100)
        mediaPlayer?.audio?.volume = Int32(v)
    }

    func setRate(_ rate: Float) {
        self.rate = rate
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        mediaPlayer?.rate = rate
#endif
    }

    func selectAudioIndex(_ index: Int) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        mediaPlayer?.currentAudioTrackIndex = Int32(index)
        selectedAudioIndex = index
#endif
    }

    /// Select audio using Plex metadata (language / title / embedded order).
    /// If tracks are not enumerated yet, keeps `pending*` and retries via `scheduleTrackRefreshAndApply`.
    func applyPlexAudio(stream: PlexStream?, allAudioStreams: [PlexStream]) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        pendingAudioStream = stream
        pendingAudioAll = allAudioStreams
        pendingAudioPlexId = stream?.id
        refreshTracks()
        if tryApplyPendingAudio() {
            return
        }
        // Tracks not ready — schedule aggressive retries
        scheduleTrackRefreshAndApply()
#endif
    }

    /// Returns true when a pending audio preference was applied successfully.
    @discardableResult
    func tryApplyPendingAudio() -> Bool {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        refreshTracks()
        guard let stream = pendingAudioStream else { return pendingAudioPlexId == nil }
        guard !audioTracks.isEmpty else { return false }
        if let idx = matchAudioTrack(for: stream, all: pendingAudioAll) {
            selectAudioIndex(idx)
            // Keep pending so late track-list reshuffles can re-assert preference
            return true
        }
        return false
#else
        return true
#endif
    }

    private func matchAudioTrack(for stream: PlexStream, all: [PlexStream]) -> Int? {
        guard !audioTracks.isEmpty else { return nil }
        let needles = Self.audioNeedles(for: stream)

        // 1) Language / name overlap with VLC track name
        if let hit = audioTracks.first(where: { track in
            let name = track.name.lowercased()
            return needles.contains { !$0.isEmpty && name.contains($0) }
        }) {
            return hit.index
        }

        // 2) Same order among embedded audio streams (Plex list vs VLC list)
        let embedded = all.filter { $0.streamType == .audio }
        if let order = embedded.firstIndex(where: { $0.id == stream.id }),
           order < audioTracks.count {
            return audioTracks[order].index
        }

        // 3) Single audio track — must be it
        if audioTracks.count == 1 {
            return audioTracks[0].index
        }
        return nil
    }

    private static func audioNeedles(for stream: PlexStream) -> [String] {
        var set = Set<String>()
        for raw in [stream.languageCode, stream.language, stream.displayTitle, stream.title]
            .compactMap({ $0?.lowercased() }) where !raw.isEmpty {
            set.insert(raw)
            let base = String(raw.prefix(while: { $0.isLetter }))
            if base.count >= 2 { set.insert(base) }
        }
        let aliases: [String: [String]] = [
            "zh": ["chi", "zho", "chinese", "cmn", "yue", "mandarin", "cantonese", "中文", "国语", "粤语"],
            "en": ["eng", "english"],
            "ja": ["jpn", "japanese", "日本語"],
            "ko": ["kor", "korean", "한국어"],
            "es": ["spa", "spanish"],
            "fr": ["fre", "fra", "french"],
            "de": ["ger", "deu", "german"],
            "pt": ["por", "portuguese"],
            "ru": ["rus", "russian"],
        ]
        for key in Array(set) {
            let base = String(key.prefix(while: { $0.isLetter }))
            if let list = aliases[base] {
                list.forEach { set.insert($0) }
            }
            for (k, list) in aliases where list.contains(key) || list.contains(base) {
                set.insert(k)
                list.forEach { set.insert($0) }
            }
        }
        return Array(set).filter { $0.count >= 2 }
    }

    func selectSubtitleIndex(_ index: Int?) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        if let index {
            mediaPlayer?.currentVideoSubTitleIndex = Int32(index)
            selectedSubtitleIndex = index
            // Keep pending* so late track reshuffles can re-assert preference
        } else {
            mediaPlayer?.currentVideoSubTitleIndex = -1
            selectedSubtitleIndex = -1
            pendingSubtitlePlexId = nil
            pendingSubtitleStream = nil
        }
#endif
    }

    /// Select subtitle using Plex metadata (language / order / external URL).
    /// External SRT/ASS are downloaded then attached as slaves; tracks may appear late — retries apply.
    func applyPlexSubtitle(
        stream: PlexStream?,
        allSubtitleStreams: [PlexStream],
        resolveExternalURL: @escaping (PlexStream) -> URL?
    ) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        pendingSubtitleAll = allSubtitleStreams
        pendingSubtitleResolve = resolveExternalURL
        guard let stream else {
            pendingSubtitleStream = nil
            pendingSubtitlePlexId = nil
            selectSubtitleIndex(nil)
            return
        }
        pendingSubtitleStream = stream
        pendingSubtitlePlexId = stream.id
        refreshTracks()

        let codec = (stream.codec ?? stream.format ?? "").lowercased()
        let treatExternal = stream.isExternal
            || stream.key != nil
            || ["srt", "ass", "ssa", "vtt", "subrip", "webvtt"].contains(codec)

        if treatExternal {
            pendingEnforceExternal = true
            if let url = resolveExternalURL(stream) {
                Task { @MainActor in
                    await self.attachExternalSubtitleWithRetry(url: url, enforce: true)
                    _ = self.tryApplyPendingSubtitle()
                    self.scheduleTrackRefreshAndApply()
                }
            } else {
                scheduleTrackRefreshAndApply()
            }
            return
        }

        pendingEnforceExternal = false
        if tryApplyPendingSubtitle() {
            return
        }
        scheduleTrackRefreshAndApply()
#endif
    }

    /// Apply pending subtitle preference once tracks / slaves are available.
    @discardableResult
    func tryApplyPendingSubtitle() -> Bool {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        refreshTracks()
        guard let stream = pendingSubtitleStream else {
            return pendingSubtitlePlexId == nil
        }
        // Prefer language match among current tracks
        if let matched = matchEmbeddedTrack(for: stream, all: pendingSubtitleAll) {
            selectSubtitleIndex(matched)
            return true
        }
        // After external attach, VLC often appends slave as last track
        if pendingEnforceExternal, let last = subtitleTracks.last {
            selectSubtitleIndex(last.index)
            return true
        }
        // Single text track
        if subtitleTracks.count == 1 {
            selectSubtitleIndex(subtitleTracks[0].index)
            return true
        }
        return false
#else
        return true
#endif
    }

    /// Fetch subtitle bytes (with token URL) to a temp file and add as VLC slave.
    @MainActor
    private func attachExternalSubtitle(url: URL, enforce: Bool) async {
        await attachExternalSubtitleWithRetry(url: url, enforce: enforce, attempts: 1)
    }

    @MainActor
    private func attachExternalSubtitleWithRetry(url: URL, enforce: Bool, attempts: Int = 3) async {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        let ext: String = {
            let path = url.path.lowercased()
            if path.hasSuffix(".ass") || path.hasSuffix(".ssa") { return "ass" }
            if path.hasSuffix(".vtt") { return "vtt" }
            return "srt"
        }()

        for attempt in 0..<max(1, attempts) {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(UInt64(400 * attempt)))
            }
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 25
                for (k, v) in httpHeaders {
                    request.setValue(v, forHTTPHeaderField: k)
                }
                // PMS often needs token on query already; also send as header
                if request.value(forHTTPHeaderField: "X-Plex-Token") == nil,
                   let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value {
                    request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
                }
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    continue
                }
                guard !data.isEmpty else { continue }
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent("plex-sub-\(UUID().uuidString).\(ext)")
                try data.write(to: tmp, options: .atomic)
                attachedExternalFileURLs.append(tmp)
                _ = mediaPlayer.addPlaybackSlave(tmp, type: .subtitle, enforce: enforce)
                // Give VLC a moment to register the slave track
                try? await Task.sleep(for: .milliseconds(250))
                refreshTracks()
                return
            } catch {
                if attempt == attempts - 1 {
                    _ = mediaPlayer.addPlaybackSlave(url, type: .subtitle, enforce: enforce)
                    try? await Task.sleep(for: .milliseconds(300))
                    refreshTracks()
                }
            }
        }
#endif
    }

    private func matchEmbeddedTrack(for stream: PlexStream, all: [PlexStream]) -> Int? {
        let needles: [String] = [
            stream.languageCode,
            stream.language,
            stream.displayTitle,
            stream.extendedDisplayTitle,
            stream.title
        ]
        .compactMap { $0?.lowercased() }
        .filter { !$0.isEmpty }

        for track in subtitleTracks {
            let name = track.name.lowercased()
            for n in needles where name.contains(n) {
                return track.index
            }
        }

        let embedded = all.filter { !$0.isExternal }
        if let order = embedded.firstIndex(where: { $0.id == stream.id }),
           order < subtitleTracks.count {
            return subtitleTracks[order].index
        }
        return nil
    }

    func refreshTracks() {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        var audio: [(Int, String)] = []
        if let indexes = mediaPlayer.audioTrackIndexes as? [NSNumber],
           let names = mediaPlayer.audioTrackNames as? [String] {
            for (i, idx) in indexes.enumerated() {
                let name = i < names.count ? names[i] : "Audio \(idx.intValue)"
                if idx.intValue >= 0 {
                    audio.append((idx.intValue, name))
                }
            }
        }
        audioTracks = audio
        selectedAudioIndex = Int(mediaPlayer.currentAudioTrackIndex)

        var subs: [(Int, String)] = []
        if let indexes = mediaPlayer.videoSubTitlesIndexes as? [NSNumber],
           let names = mediaPlayer.videoSubTitlesNames as? [String] {
            for (i, idx) in indexes.enumerated() {
                let name = i < names.count ? names[i] : "Subtitle \(idx.intValue)"
                if idx.intValue >= 0 {
                    subs.append((idx.intValue, name))
                }
            }
        }
        subtitleTracks = subs
        selectedSubtitleIndex = Int(mediaPlayer.currentVideoSubTitleIndex)
        if pendingAudioStream != nil {
            _ = tryApplyPendingAudio()
        }
        if pendingSubtitleStream != nil {
            _ = tryApplyPendingSubtitle()
        }
        onTracksUpdated?()
#endif
    }

    private func scheduleTrackRefreshAndApply() {
        trackApplyTask?.cancel()
        trackApplyTask = Task { @MainActor in
            // VLC may expose tracks only after buffering/playing (multi-second on some streams).
            let delays: [UInt64] = [150, 400, 800, 1200, 2000, 3500, 5000, 8000]
            for delay in delays {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                refreshTracks()
                let audioOK = tryApplyPendingAudio()
                let subOK = tryApplyPendingSubtitle()
                // Retry external download if still missing tracks
                if !subOK, let stream = pendingSubtitleStream, pendingEnforceExternal,
                   let resolve = pendingSubtitleResolve, let url = resolve(stream) {
                    await attachExternalSubtitleWithRetry(url: url, enforce: true, attempts: 2)
                    _ = tryApplyPendingSubtitle()
                }
                if audioOK || (pendingAudioStream == nil), subOK || (pendingSubtitleStream == nil) {
                    if (pendingAudioStream == nil || audioOK), (pendingSubtitleStream == nil || tryApplyPendingSubtitle()) {
                        try? await Task.sleep(for: .milliseconds(700))
                        guard !Task.isCancelled else { return }
                        refreshTracks()
                        _ = tryApplyPendingAudio()
                        _ = tryApplyPendingSubtitle()
                        return
                    }
                }
            }
        }
    }

    private func stopInternal() {
        trackApplyTask?.cancel()
        trackApplyTask = nil
        timeTimer?.invalidate()
        timeTimer = nil
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        mediaPlayer?.stop()
        mediaPlayer?.delegate = nil
        mediaPlayer = nil
#endif
        positionMs = 0
        durationMs = 0
        audioTracks = []
        subtitleTracks = []
        pendingSubtitlePlexId = nil
        pendingSubtitleStream = nil
        pendingSubtitleAll = []
        pendingSubtitleResolve = nil
        pendingEnforceExternal = false
        pendingAudioPlexId = nil
        pendingAudioStream = nil
        pendingAudioAll = []
        externalSubtitleURLs = []
        for u in attachedExternalFileURLs {
            try? FileManager.default.removeItem(at: u)
        }
        attachedExternalFileURLs = []
    }

    private func startTimePolling() {
        timeTimer?.invalidate()
        timeTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollTime()
            }
        }
    }

    private func pollTime() {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        positionMs = Int64(mediaPlayer.time.intValue)
        if let media = mediaPlayer.media {
            let len = Int(media.length.intValue)
            if len > 0 {
                durationMs = Int64(len)
            }
            sampleThroughput(from: media)
        }
        onTimeChange?(positionMs, durationMs)
#endif
    }

#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
    private func sampleThroughput(from media: VLCMedia) {
        // VLCMedia.Stats may be a struct (SPM) — use Mirror, avoid NSObject cast.
        let mirror = Mirror(reflecting: media.statistics)
        var demux: Double?
        var input: Double?
        for child in mirror.children {
            guard let label = child.label?.lowercased() else { continue }
            let value: Double?
            switch child.value {
            case let d as Double: value = d
            case let f as Float: value = Double(f)
            case let i as Int: value = Double(i)
            case let i as Int32: value = Double(i)
            case let n as NSNumber: value = n.doubleValue
            default: value = nil
            }
            guard let value, value > 0 else { continue }
            if label.contains("demux") && label.contains("bit") { demux = value }
            if label.contains("input") && label.contains("bit") { input = value }
        }
        guard let raw = demux ?? input else { return }
        let mbps: Double
        if raw > 100_000 {
            mbps = raw / 1_000_000
        } else if raw > 50 {
            mbps = (raw * 8) / 1_000_000
        } else {
            mbps = raw
        }
        guard mbps > 0.05, mbps < 500 else { return }
        throughputSamples.append(mbps)
        if throughputSamples.count > 10 {
            throughputSamples.removeFirst(throughputSamples.count - 10)
        }
        let avg = throughputSamples.reduce(0, +) / Double(throughputSamples.count)
        estimatedThroughputMbps = avg
        onThroughputMbps?(avg)
    }
#endif
}

#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
extension VLCPlaybackBackend: VLCMediaPlayerDelegate {
    nonisolated func mediaPlayerStateChanged(_ aNotification: Notification) {
        Task { @MainActor in
            guard let mediaPlayer else { return }
            switch mediaPlayer.state {
            case .buffering:
                state = .buffering
                onStateChange?(.buffering)
            case .playing:
                state = .playing
                onStateChange?(.playing)
                refreshTracks()
                // Video size is often 0 until playing — re-apply fill/stretch crop.
                applyAspectMode(aspectMode)
            case .paused:
                state = .paused
                onStateChange?(.paused)
            case .stopped:
                state = .stopped
                onStateChange?(.stopped)
            case .ended:
                state = .stopped
                onStateChange?(.stopped)
                onEnded?()
            case .error:
                state = .failed
                onStateChange?(.failed)
                onError?("VLC playback error")
            default:
                break
            }
        }
    }

    nonisolated func mediaPlayerTimeChanged(_ aNotification: Notification) {
        Task { @MainActor in
            pollTime()
        }
    }
}
#endif
