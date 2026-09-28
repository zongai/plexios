import Foundation

/// Native A/V pipeline loop: demux → decode → sync present.
/// Phase 6: runnable when demuxer yields packets; with Builtin demuxer, packet path is limited.
final class PlaybackPipeline: @unchecked Sendable {
    enum State: String, Sendable {
        case idle
        case loading
        case buffering
        case playing
        case paused
        case seeking
        case failed
        case stopped
    }

    private let lock = NSLock()
    private(set) var state: State = .idle
    private(set) var lastError: String?

    let clock = MediaClock()
    let buffers = BufferManager()
    let seekController = SeekController()
    let frameSink = VideoFrameSink()

    private var demuxer: (any Demuxer)?
    private var videoDecoder: (any VideoDecoder)?
    private var audioHub: AudioEngineHub?
    private var metalPresenter: MetalVideoRenderer.Presenter?

    private var pipelineTask: Task<Void, Never>?
    private var videoConfig: VideoDecoderConfig?
    private var audioConfig: AudioDecoderConfig?
    let subtitleController = SubtitleTrackController()
    private var subtitleFormat: SubtitleFormat = .unknown
    private var bitmapFormat: BitmapSubtitleFormat = .unknown
    private var bitmapDecoder: (any BitmapSubtitleDecoder)?
    private(set) var bitmapCues: [BitmapSubtitleCue] = []

    /// Drop video frame if ahead of clock by more than this (ms).
    var maxVideoLeadMs: Int64 = 40
    /// Wait (don't present) if behind by more than this.
    var maxVideoLagMs: Int64 = 80

    // MARK: - Lifecycle

    func configure(
        video: VideoDecoderConfig?,
        audio: AudioDecoderConfig?,
        presenter: MetalVideoRenderer.Presenter?,
        subtitleFormat: SubtitleFormat = .unknown,
        bitmapFormat: BitmapSubtitleFormat = .unknown
    ) {
        lock.lock()
        videoConfig = video
        audioConfig = audio
        metalPresenter = presenter
        self.subtitleFormat = subtitleFormat
        self.bitmapFormat = bitmapFormat
        if bitmapFormat != .unknown {
            bitmapDecoder = try? BitmapSubtitleDecoderFactory.make(format: bitmapFormat)
        } else {
            bitmapDecoder = nil
        }
        bitmapCues = []
        lock.unlock()
    }

    func start(demuxer: any Demuxer, startMs: Int64 = 0) async {
        await stop()
        self.demuxer = demuxer
        clock.reset(startMs: startMs)
        buffers.flushAll()
        lastError = nil

        do {
            if let videoConfig {
                let outcome = VideoDecodeFallbackChain.open(codec: videoConfig.codec)
                let dec = try VideoDecodeFallbackChain.setup(outcome, config: videoConfig)
                videoDecoder = dec
                if outcome.stage == .software {
                    // Soft path — diagnostics
                }
            }
            if let audioConfig {
                let hub = AudioEngineHub()
                try hub.setup(config: audioConfig)
                audioHub = hub
            }
        } catch {
            fail(error.localizedDescription)
            return
        }

        setState(.loading)
        pipelineTask = Task { [weak self] in
            await self?.runLoop()
        }
    }

    func pause() {
        clock.pause()
        audioHub?.pause()
        setState(.paused)
    }

    func resume() {
        clock.resume()
        audioHub?.play()
        setState(.playing)
    }

    func seek(toMs ms: Int64) async {
        seekController.begin(targetMs: ms)
        setState(.seeking)
        buffers.flushAll()
        videoDecoder?.flush()
        audioHub?.flush()
        clock.seek(toMs: ms)
        do {
            try await demuxer?.seek(toMs: ms)
        } catch {
            // Builtin demux may not support seek
            lastError = error.localizedDescription
        }
        seekController.complete()
        if state != .paused {
            setState(.playing)
        }
    }

    func stop() async {
        pipelineTask?.cancel()
        pipelineTask = nil
        videoDecoder?.invalidate()
        videoDecoder = nil
        audioHub?.stop()
        audioHub = nil
        await demuxer?.close()
        demuxer = nil
        buffers.flushAll()
        await MainActor.run { frameSink.clear() }
        metalPresenter?.clear()
        setState(.stopped)
    }

    // MARK: - Loop

    private func runLoop() async {
        setState(.buffering)
        while !Task.isCancelled {
            if state == .paused {
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }
            if state == .stopped || state == .failed { break }

            // Demux fill
            await fillFromDemuxer()

            // Decode
            decodeAvailable()

            // Startup gate
            if state == .loading || state == .buffering {
                if buffers.hasStartupBuffer() {
                    setState(.playing)
                    audioHub?.play()
                } else if buffers.needsRebuffer() {
                    setState(.buffering)
                }
            }

            if state == .playing {
                presentVideoFrame()
                presentAudioFrames()
                if buffers.needsRebuffer() {
                    setState(.buffering)
                    clock.pause()
                }
            }

            if state == .buffering, buffers.hasStartupBuffer() {
                clock.resume()
                setState(.playing)
                audioHub?.play()
            }

            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func fillFromDemuxer() async {
        guard let demuxer else { return }
        let counts = buffers.counts()
        // Keep some headroom
        for _ in 0..<8 {
            if counts.vPkt + counts.aPkt > 100 { break }
            do {
                guard let packet = try await demuxer.nextPacket() else { break }
                _ = buffers.pushPacket(packet)
            } catch {
                if case DemuxError.ffmpegNotLinked = error {
                    // Probe-only demuxer — stop filling
                    break
                }
                if case DemuxError.endOfStream = error {
                    break
                }
                // Other errors: surface once
                lastError = error.localizedDescription
                break
            }
        }
    }

    private func decodeAvailable() {
        // Video
        if let videoDecoder {
            while let pkt = buffers.popVideoPacket() {
                do {
                    let frames = try videoDecoder.decode(packet: pkt)
                    for f in frames {
                        if !buffers.pushVideoFrame(f) { break }
                    }
                } catch {
                    lastError = error.localizedDescription
                    break
                }
            }
        }
        // Audio
        
        // Subtitle packets → text or bitmap cues
        while let pkt = buffers.popSubtitlePacket() {
            if bitmapFormat != .unknown, let bitmapDecoder {
                do {
                    let cues = try bitmapDecoder.push(packet: pkt)
                    if !cues.isEmpty {
                        lock.lock()
                        bitmapCues.append(contentsOf: cues)
                        lock.unlock()
                    }
                } catch {
                    lastError = error.localizedDescription
                }
            } else if subtitleFormat != .unknown {
                do {
                    let decoder = try SubtitleDecoderFactory.make(format: subtitleFormat)
                    let cues = try decoder.decode(packet: pkt)
                    subtitleController.append(cues)
                } catch {
                    lastError = error.localizedDescription
                }
            }
        }

        if let audioHub {
            while let pkt = buffers.popAudioPacket() {
                do {
                    try audioHub.push(packet: pkt)
                    // Also keep frames for clock if needed — hub renders directly
                } catch {
                    lastError = error.localizedDescription
                    break
                }
            }
        }
    }

    private func presentVideoFrame() {
        guard let frame = buffers.peekVideoFrame() else { return }
        let pts = frame.ptsMs ?? clock.currentMediaTimeMs()
        let skew = clock.videoSkewMs(videoPts: pts)

        if skew > maxVideoLeadMs {
            // Early — wait
            return
        }
        if skew < -maxVideoLagMs {
            // Late — drop
            _ = buffers.popVideoFrame()
            return
        }

        _ = buffers.popVideoFrame()
        clock.setVideoPts(pts)
        Task { @MainActor in
            frameSink.present(frame)
        }
        metalPresenter?.present(frame)
    }

    private func presentAudioFrames() {
        if let t = audioHub?.currentTimeMs() {
            clock.setAudioPts(t)
        }
    }

    private func setState(_ s: State) {
        lock.lock()
        state = s
        lock.unlock()
    }

    private func fail(_ message: String) {
        lastError = message
        setState(.failed)
    }
}
