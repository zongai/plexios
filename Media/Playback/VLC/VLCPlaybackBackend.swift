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

    /// Call after rotation / container layout so VLC uses non-zero landscape bounds.
    func rebindDrawable() {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        drawableView.setNeedsLayout()
        drawableView.layoutIfNeeded()
        mediaPlayer.drawable = nil
        mediaPlayer.drawable = drawableView
#endif
    }

#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
    private var mediaPlayer: VLCMediaPlayer?
#endif

    private var timeTimer: Timer?
    private var pendingSubtitlePlexId: Int?
    private var externalSubtitleURLs: [URL] = []
    private var httpHeaders: [String: String] = [:]

    /// - Parameters:
    ///   - externalSubtitles: Plex external subtitle file URLs (with token if needed).
    ///   - preferredSubtitlePlexId: Plex stream id to enable once tracks appear.
    func prepare(
        url: URL,
        headers: [String: String],
        startPositionMs: Int64,
        externalSubtitles: [URL] = [],
        preferredSubtitlePlexId: Int? = nil,
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

    func selectSubtitleIndex(_ index: Int?) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        if let index {
            mediaPlayer?.currentVideoSubTitleIndex = Int32(index)
            selectedSubtitleIndex = index
            pendingSubtitlePlexId = nil
        } else {
            mediaPlayer?.currentVideoSubTitleIndex = -1
            selectedSubtitleIndex = -1
            pendingSubtitlePlexId = nil
        }
#endif
    }

    /// Select subtitle using Plex metadata (language / order / external URL).
    func applyPlexSubtitle(
        stream: PlexStream?,
        allSubtitleStreams: [PlexStream],
        resolveExternalURL: (PlexStream) -> URL?
    ) {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        refreshTracks()

        guard let stream else {
            selectSubtitleIndex(nil)
            return
        }

        pendingSubtitlePlexId = stream.id

        // External / sidecar text → download + slave
        let codec = (stream.codec ?? stream.format ?? "").lowercased()
        let treatExternal = stream.isExternal
            || stream.key != nil
            || ["srt", "ass", "ssa", "vtt", "subrip", "webvtt"].contains(codec)
        if treatExternal {
            if let url = resolveExternalURL(stream) {
                Task { @MainActor in
                    await self.attachExternalSubtitle(url: url, enforce: true)
                    try? await Task.sleep(for: .milliseconds(300))
                    self.refreshTracks()
                    if let last = self.subtitleTracks.last {
                        self.selectSubtitleIndex(last.index)
                    } else {
                        // Retry once
                        try? await Task.sleep(for: .milliseconds(500))
                        self.refreshTracks()
                        if let last = self.subtitleTracks.last {
                            self.selectSubtitleIndex(last.index)
                        }
                    }
                }
            }
            return
        }

        // Embedded: match by language code / name, else by order among embedded streams
        if let matched = matchEmbeddedTrack(for: stream, all: allSubtitleStreams) {
            selectSubtitleIndex(matched)
            return
        }

        // Retry shortly — tracks may not be enumerated yet
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            self.refreshTracks()
            if let matched = self.matchEmbeddedTrack(for: stream, all: allSubtitleStreams) {
                self.selectSubtitleIndex(matched)
            } else if let first = self.subtitleTracks.first {
                // Last resort: first available text track
                self.selectSubtitleIndex(first.index)
            }
        }
#endif
    }


    /// Fetch subtitle bytes (with token URL) to a temp file and add as VLC slave.
    @MainActor
    private func attachExternalSubtitle(url: URL, enforce: Bool) async {
#if canImport(VLCKitSPM) || canImport(MobileVLCKit)
        guard let mediaPlayer else { return }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            // Token is usually in query; still forward plex identity headers if present on media.
            for (k, v) in httpHeaders {
                request.setValue(v, forHTTPHeaderField: k)
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                return
            }
            guard !data.isEmpty else { return }
            let ext: String = {
                let path = url.path.lowercased()
                if path.hasSuffix(".ass") || path.hasSuffix(".ssa") { return "ass" }
                if path.hasSuffix(".vtt") { return "vtt" }
                return "srt"
            }()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("plex-sub-\(UUID().uuidString).\(ext)")
            try data.write(to: tmp, options: .atomic)
            // addPlaybackSlave returns Int32 in some MobileVLCKit versions (0 = fail).
            let result = mediaPlayer.addPlaybackSlave(tmp, type: .subtitle, enforce: enforce)
            if result == 0 {
                _ = mediaPlayer.addPlaybackSlave(url, type: .subtitle, enforce: enforce)
            }
        } catch {
            _ = mediaPlayer.addPlaybackSlave(url, type: .subtitle, enforce: enforce)
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
        onTracksUpdated?()
#endif
    }

    private func scheduleTrackRefreshAndApply() {
        Task { @MainActor in
            for delay in [300, 800, 1500] as [UInt64] {
                try? await Task.sleep(for: .milliseconds(delay))
                refreshTracks()
                if let pending = pendingSubtitlePlexId, !subtitleTracks.isEmpty {
                    // Caller should call applyPlexSubtitle; here just keep tracks fresh.
                    _ = pending
                }
            }
        }
    }

    private func stopInternal() {
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
        externalSubtitleURLs = []
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
