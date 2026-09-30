import AVFoundation
import Foundation

/// Configures AVAudioSession for playback, AirPlay, and handles interruptions.
@MainActor
final class AudioSessionCoordinator {
    private weak var engine: PlaybackEngine?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var wasPlayingBeforeInterruption = false
    private let logger: LogRouter

    init(logger: LogRouter) {
        self.logger = logger
    }

    func attach(to engine: PlaybackEngine) {
        self.engine = engine
        startObserving()
    }

    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        // Prefer full options; OSStatus -50 (paramErr) is common when the
        // previous route/category combination is incompatible — fall back.
        do {
            try session.setCategory(
                .playback,
                mode: .moviePlayback,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            try session.setActive(true)
            logger.playback.debug("Audio session activated (moviePlayback + AirPlay/A2DP)")
            return
        } catch {
            logger.playback.warning("Audio session primary activate failed: \(error.localizedDescription)")
        }
        do {
            try session.setCategory(.playback, mode: .default, options: [.allowAirPlay])
            try session.setActive(true)
            logger.playback.debug("Audio session activated (fallback default + AirPlay)")
            return
        } catch {
            logger.playback.warning("Audio session fallback activate failed: \(error.localizedDescription)")
        }
        try session.setCategory(.playback)
        try session.setActive(true)
        logger.playback.debug("Audio session activated (minimal playback)")
    }

    func deactivate(notifyOthers: Bool = false) {
        do {
            try AVAudioSession.sharedInstance().setActive(
                false,
                options: notifyOthers ? [.notifyOthersOnDeactivation] : []
            )
        } catch {
            logger.playback.error("Audio session deactivate: \(error.localizedDescription)")
        }
    }

    private func startObserving() {
        stopObserving()

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleInterruption(notification)
            }
        }

        routeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleRouteChange(notification)
            }
        }
    }

    func stopObserving() {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let routeObserver {
            NotificationCenter.default.removeObserver(routeObserver)
        }
        interruptionObserver = nil
        routeObserver = nil
    }

    private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            wasPlayingBeforeInterruption = engine?.isPlaying ?? false
            engine?.pause()
            logger.playback.info("Interruption began")
        case .ended:
            let options = (info[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            logger.playback.info("Interruption ended shouldResume=\(options.contains(.shouldResume))")
            if options.contains(.shouldResume), wasPlayingBeforeInterruption {
                do {
                    try activate()
                    engine?.resume()
                } catch {
                    logger.playback.error("Resume after interruption failed: \(error.localizedDescription)")
                }
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
            let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { return }

        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged — pause for safety
            engine?.pause()
            logger.playback.info("Route change: old device unavailable — paused")
        case .newDeviceAvailable:
            logger.playback.debug("Route change: new device available")
        default:
            break
        }
    }
}
