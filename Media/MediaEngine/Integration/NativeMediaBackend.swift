import Foundation
import Observation

/// Native Media Engine backend. Phase 6: hosts PlaybackPipeline.
/// Full playback still requires FFmpeg demux packets (Phase 2 complete + NATIVE_FFMPEG).
@Observable
@MainActor
final class NativeMediaBackend: PlayerEngineBackend {
    let backendKind: PlaybackBackend = .nativeMediaEngine
    private(set) var state: MediaEngineSessionState = .idle
    private(set) var positionMs: Int64 = 0
    private(set) var durationMs: Int64 = 0
    private(set) var rate: Float = 1.0

    private let logger: LogRouter
    private let pipeline = PlaybackPipeline()
    private var positionTimer: Task<Void, Never>?

    init(logger: LogRouter) {
        self.logger = logger
    }

    func prepare(request: PlaybackRequest) async throws {
        state = .loading
        logger.playback.info(
            "NativeMediaBackend prepare path=\(request.path.rawValue)"
        )

        // Prefer real demux when available; Builtin cannot yield packets → cannot sustain play.
        let demuxer = DemuxerFactory.make()
        do {
            try await demuxer.open(url: request.mediaURL, headers: [
                "X-Plex-Token": request.context.token,
                "Accept": "*/*"
            ])
        } catch {
            state = .failed
            throw PlaybackFailure(
                stage: .demux,
                reason: "Demux open failed: \(error.localizedDescription)",
                underlying: String(describing: error)
            )
        }

        let media = request.metadata.media[safe: request.decision.mediaIndex]
        let part = media?.parts[safe: request.decision.partIndex]
        let videoStream = part?.streams.first { $0.streamType == .video }
        let audioStream = part?.streams.first { $0.streamType == .audio }

        let vCodec = VideoCodecID.from(codecName: videoStream?.codec ?? media?.videoCodec)
        let aCodec = AudioCodecID.from(codecName: audioStream?.codec ?? media?.audioCodec)

        var videoConfig: VideoDecoderConfig?
        if vCodec != .unknown {
            videoConfig = VideoDecoderConfig(
                codec: vCodec,
                width: media?.width ?? 1920,
                height: media?.height ?? 1080,
                extradata: nil,
                bitDepth: videoStream?.bitDepth ?? 8
            )
        }
        var audioConfig: AudioDecoderConfig?
        if aCodec != .unknown {
            audioConfig = AudioDecoderConfig(
                codec: aCodec,
                sampleRate: 48_000,
                channels: audioStream?.channels ?? 2,
                extradata: nil,
                bitDepth: 16
            )
        }

        pipeline.configure(video: videoConfig, audio: audioConfig, presenter: nil)
        durationMs = request.metadata.duration ?? part?.duration ?? 0
        rate = Float(request.preferences.defaultPlaybackRate)

        // Builtin demuxer is probe-only (no packets). Fail fast → AVPlayer fallback.
        // Do not call nextPacket() first: that would drop the first media packet when FFmpeg is linked.
        #if !NATIVE_FFMPEG
        await demuxer.close()
        state = .failed
        throw PlaybackFailure(
            stage: .demux,
            reason: "Native demux has no packets (link NATIVE_FFMPEG for full engine). Falling back.",
            underlying: "BuiltinContainerDemuxer is probe-only"
        )
        #else
        await pipeline.start(demuxer: demuxer, startMs: request.startPositionMs)
        pipeline.clock.playbackRate = Double(rate)
        state = .playing
        startPositionPolling()
        #endif
    }

    func play() {
        pipeline.resume()
        state = .playing
    }

    func pause() {
        pipeline.pause()
        state = .paused
    }

    func stop() async {
        positionTimer?.cancel()
        positionTimer = nil
        await pipeline.stop()
        state = .stopped
        positionMs = 0
    }

    func seek(toMs ms: Int64) async {
        state = .seeking
        await pipeline.seek(toMs: ms)
        positionMs = ms
        state = .playing
    }

    func setRate(_ rate: Float) {
        self.rate = rate
        pipeline.clock.playbackRate = Double(rate)
        // Audio hub rate updated inside pipeline on next design pass
    }

    func selectAudio(streamId: Int) async {}
    func selectSubtitle(streamId: Int?) async {}

    private func startPositionPolling() {
        positionTimer?.cancel()
        positionTimer = Task { [weak self] in
            while !Task.isCancelled {
                await MainActor.run {
                    guard let self else { return }
                    self.positionMs = self.pipeline.clock.currentMediaTimeMs()
                    if self.pipeline.state == .failed {
                        self.state = .failed
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
