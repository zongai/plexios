import Foundation
import MediaPlayer
import UIKit

/// Updates MPNowPlayingInfoCenter with title, artwork, progress, rate.
@MainActor
final class NowPlayingController {
    private let logger: LogRouter
    private var artworkTask: Task<Void, Never>?

    init(logger: LogRouter) {
        self.logger = logger
    }

    func update(
        metadata: PlexMetadata,
        positionMs: Int64,
        durationMs: Int64,
        isPlaying: Bool,
        artworkURL: URL?
    ) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        info[MPMediaItemPropertyTitle] = metadata.title
        if let show = metadata.grandparentTitle ?? metadata.parentTitle {
            info[MPMediaItemPropertyAlbumTitle] = show
        }
        if let year = metadata.year {
            info[MPMediaItemPropertyAlbumArtist] = String(year)
        }

        if durationMs > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.video.rawValue

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if let artworkURL {
            loadArtwork(from: artworkURL)
        }
    }

    func updateProgress(positionMs: Int64, durationMs: Int64, isPlaying: Bool) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = Double(positionMs) / 1000.0
        if durationMs > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000.0
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clear() {
        artworkTask?.cancel()
        artworkTask = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(from url: URL) {
        artworkTask?.cancel()
        artworkTask = Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled, let image = UIImage(data: data) else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            } catch {
                logger.playback.debug("Artwork load failed: \(error.localizedDescription)")
            }
        }
    }
}
