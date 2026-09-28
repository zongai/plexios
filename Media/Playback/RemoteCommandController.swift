import Foundation
import MediaPlayer

/// Wires MPRemoteCommandCenter to PlaybackEngine intents.
@MainActor
final class RemoteCommandController {
    private weak var engine: PlaybackEngine?
    private var configured = false

    func attach(to engine: PlaybackEngine) {
        self.engine = engine
        guard !configured else { return }
        configured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            self?.engine?.resume()
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            self?.engine?.pause()
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.engine?.togglePlayPause()
            return .success
        }

        center.stopCommand.isEnabled = true
        center.stopCommand.addTarget { [weak self] _ in
            Task { await self?.engine?.stop(report: true) }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] event in
            let seconds = Int64((event as? MPSkipIntervalCommandEvent)?.interval ?? 10)
            Task { await self?.engine?.skip(seconds: seconds) }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] event in
            let seconds = Int64((event as? MPSkipIntervalCommandEvent)?.interval ?? 10)
            Task { await self?.engine?.skip(seconds: -seconds) }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let ms = Int64(event.positionTime * 1000)
            Task { await self?.engine?.seek(toMs: ms) }
            return .success
        }

        // Next / previous reserved for episode navigation (Phase polish)
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    func detach() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.removeTarget(nil)
        center.pauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.removeTarget(nil)
        center.stopCommand.removeTarget(nil)
        center.skipForwardCommand.removeTarget(nil)
        center.skipBackwardCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.removeTarget(nil)
        configured = false
        engine = nil
    }
}
