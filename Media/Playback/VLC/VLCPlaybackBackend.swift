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

    /// Pixel size of the decoded video (0 if not yet known). Used by VLCPlayerContainer layout.
    var currentVideoSize: CGSize {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return .zero }
        let s = mediaPlayer.videoSize
        return CGSize(width: CGFloat(s.width), height: CGFloat(s.height))
#else
        return .zero
#endif
    }

    /// Call after rotation / container layout so VLC uses non-zero landscape bounds.
    func rebindDrawable() {
        rebindDrawablePreservingAspect()
    }

    /// Re-attach drawable without touching VLC aspect/crop C-string APIs.
    func rebindDrawablePreservingAspect() {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        drawableView.setNeedsLayout()
        drawableView.layoutIfNeeded()
        mediaPlayer.drawable = nil
        mediaPlayer.drawable = drawableView
#endif
    }

    /// Fit / fill / stretch are applied by `VLCPlayerContainer` frame layout only.
    /// Do **not** write `videoAspectRatio` / `videoCropGeometry` (MobileVLCKit
    /// `char *` setters — strdup ownership is unsafe and has caused hard crashes
    /// on the shared Plex + IPTV VLC path since e706b0a).
    func setAspectMode(_ mode: VideoAspectMode) {
        aspectMode = mode
    }

#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
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
        /// 0-based index among audio streams (for VLC `audio-track` option before play).
        preferredAudioOrder: Int? = nil,
        /// 0-based index among embedded subtitle streams (for VLC `sub-track` option).
        preferredSubtitleOrder: Int? = nil,
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
            "freetype-rel-fontsize": 16,
            // Ensure text subs are rendered.
            "sub-autodetect-file": true
        ]
        // Prefer tracks via media options *before* play — mutating
        // currentAudioTrackIndex after play hard-crashes MobileVLCKit.
        if let preferredAudioOrder, preferredAudioOrder >= 0 {
            opts["audio-track"] = String(preferredAudioOrder)
        }
        // Embedded text: set before play. (Live currentVideoSubTitleIndex hard-crashes.)
        if let preferredSubtitleOrder, preferredSubtitleOrder >= 0 {
            opts["sub-track"] = String(preferredSubtitleOrder)
            opts["sub-track-id"] = String(preferredSubtitleOrder)
        }
        // External SRT/ASS: download to disk *before* play and bind with sub-file.
        // Post-play addPlaybackSlave without selecting a track left sidecars invisible;
        // selecting tracks live hard-crashes MobileVLCKit.
        if let firstSub = externalSubtitles.first,
           let localSub = await downloadSubtitleToTemp(url: firstSub) {
            opts["sub-file"] = localSub.path
            // Also as input-slave for builds that ignore sub-file.
            opts["input-slave"] = localSub.absoluteString
        }
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

        if startPositionMs > 0 {
            player.time = VLCTime(int: Int32(clamping: startPositionMs))
        }

        startTimePolling()
        rate = 1.0
        state = .playing
        onStateChange?(.playing)

        // Enumerate tracks for UI only (no live index writes).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard self.mediaPlayer != nil else { return }
            self.refreshTracks()
            self.onTracksUpdated?()
        }
#else
        throw PlaybackFailure(stage: .unknown, reason: "MobileVLCKit not linked", underlying: nil)
#endif
    }

    /// Download a remote subtitle (with Plex token headers) to a temp file.
    @MainActor
    private func downloadSubtitleToTemp(url: URL) async -> URL? {
        let ext: String = {
            let path = url.path.lowercased()
            if path.hasSuffix(".ass") || path.hasSuffix(".ssa") { return "ass" }
            if path.hasSuffix(".vtt") { return "vtt" }
            return "srt"
        }()
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            for (k, v) in httpHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
            if request.value(forHTTPHeaderField: "X-Plex-Token") == nil,
               let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "X-Plex-Token" })?.value {
                request.setValue(token, forHTTPHeaderField: "X-Plex-Token")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return nil
            }
            guard !data.isEmpty else { return nil }
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("plex-sub-\(UUID().uuidString).\(ext)")
            try data.write(to: tmp, options: .atomic)
            attachedExternalFileURLs.append(tmp)
            return tmp
        } catch {
            return nil
        }
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
        // VLC audio volume is 0…200 (100 = normal, 200 = +6dB-ish boost).
        // App linear scale: 0…2 → map to 0…200.
        let clamped = min(2, max(0, linear))
        let v = Int((clamped * 100).rounded())
        mediaPlayer?.audio?.volume = Int32(min(200, max(0, v)))
    }

    func setRate(_ rate: Float) {
        self.rate = rate
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        mediaPlayer?.rate = rate
#endif
    }

    func selectAudioIndex(_ index: Int) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        if index >= 0 {
            let allowed = audioTracks.map(\.index)
            if !allowed.isEmpty && !allowed.contains(index) { return }
        }
        if selectedAudioIndex == index { return }
        // Pause → set → resume: setting currentAudioTrackIndex while decoding hard-crashes.
        let wasPlaying = mediaPlayer.isPlaying
        if wasPlaying { mediaPlayer.pause() }
        mediaPlayer.currentAudioTrackIndex = Int32(index)
        selectedAudioIndex = index
        if wasPlaying { mediaPlayer.play() }
#endif
    }

    /// Select audio using Plex metadata — index only, minimal retry.
    func applyPlexAudio(stream: PlexStream?, allAudioStreams: [PlexStream]) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        pendingAudioStream = stream
        pendingAudioAll = allAudioStreams
        pendingAudioPlexId = stream?.id
        guard let stream else { return }
        refreshTracks()
        if let idx = matchAudioTrack(for: stream, all: allAudioStreams) {
            selectAudioIndex(idx)
            return
        }
        if audioTracks.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                self.refreshTracks()
                if let idx = self.matchAudioTrack(for: stream, all: allAudioStreams) {
                    self.selectAudioIndex(idx)
                }
            }
        }
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
        guard let mediaPlayer else { return }
        if let index {
            let allowed = subtitleTracks.map(\.index)
            if !allowed.isEmpty && !allowed.contains(index) { return }
            if selectedSubtitleIndex == index { return }
            let wasPlaying = mediaPlayer.isPlaying
            if wasPlaying { mediaPlayer.pause() }
            mediaPlayer.currentVideoSubTitleIndex = Int32(index)
            selectedSubtitleIndex = index
            if wasPlaying { mediaPlayer.play() }
        } else {
            if selectedSubtitleIndex == -1 { return }
            let wasPlaying = mediaPlayer.isPlaying
            if wasPlaying { mediaPlayer.pause() }
            mediaPlayer.currentVideoSubTitleIndex = -1
            selectedSubtitleIndex = -1
            pendingSubtitlePlexId = nil
            pendingSubtitleStream = nil
            if wasPlaying { mediaPlayer.play() }
        }
#endif
    }

    /// Select subtitle using Plex metadata (#62-style, safer attach).
    func applyPlexSubtitle(
        stream: PlexStream?,
        allSubtitleStreams: [PlexStream],
        resolveExternalURL: @escaping (PlexStream) -> URL?
    ) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard mediaPlayer != nil else { return }
        refreshTracks()
        pendingSubtitleAll = allSubtitleStreams
        pendingSubtitleResolve = resolveExternalURL

        guard let stream else {
            pendingSubtitleStream = nil
            pendingSubtitlePlexId = nil
            pendingEnforceExternal = false
            selectSubtitleIndex(nil)
            return
        }

        pendingSubtitleStream = stream
        pendingSubtitlePlexId = stream.id

        // Prefer already-loaded VLC track (from prepare-time attach) — index only, no re-download.
        if let matched = matchEmbeddedTrack(for: stream, all: allSubtitleStreams) {
            pendingEnforceExternal = false
            selectSubtitleIndex(matched)
            return
        }

        // Only true Plex sidecars — never treat embedded ASS/SRT as external just by codec
        // (that path used to download+slave and crash on track switch).
        let key = stream.key ?? ""
        let treatExternal = stream.isExternal
            || key.contains("/library/streams/")

        if treatExternal {
            pendingEnforceExternal = true
            guard let url = resolveExternalURL(stream) else { return }
            Task { @MainActor in
                await self.attachExternalSubtitle(url: url, enforce: false)
                try? await Task.sleep(for: .milliseconds(400))
                self.refreshTracks()
                if let last = self.subtitleTracks.last {
                    self.selectSubtitleIndex(last.index)
                }
            }
            return
        }

        // Embedded text track — index select only; one delayed retry if list empty.
        pendingEnforceExternal = false
        if subtitleTracks.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(600))
                self.refreshTracks()
                if let matched = self.matchEmbeddedTrack(for: stream, all: allSubtitleStreams) {
                    self.selectSubtitleIndex(matched)
                }
            }
        }
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
                // Local file only — remote HTTP slave URLs have hard-crashed MobileVLCKit.
                _ = mediaPlayer.addPlaybackSlave(tmp, type: .subtitle, enforce: enforce)
                try? await Task.sleep(for: .milliseconds(250))
                refreshTracks()
                return
            } catch {
                // Retry loop; no remote-URL fallback.
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
        // Intentionally minimal: only refresh track lists for UI. Never re-apply
        // currentAudioTrackIndex / subtitle index in a loop (hard-crashes VLC).
        trackApplyTask?.cancel()
        trackApplyTask = Task { @MainActor in
            for delay in [500, 1500] as [UInt64] {
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else { return }
                self.refreshTracks()
                self.onTracksUpdated?()
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
