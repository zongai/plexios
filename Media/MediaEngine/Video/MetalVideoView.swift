import MetalKit
import SwiftUI

/// UIKit host for Metal video output (Native Media Engine).
final class MetalVideoUIView: MTKView {
    let renderer: MetalVideoRenderer?

    override init(frame: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        self.renderer = MetalVideoRenderer(device: metalDevice)
        super.init(frame: frame, device: metalDevice)
        isOpaque = true
        backgroundColor = .black
        if let renderer {
            renderer.attach(to: self)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(_ frame: VideoFrame) {
        renderer?.enqueue(frame, on: self)
    }

    func setAspectMode(_ mode: VideoAspectMode) {
        renderer?.aspectMode = mode
        setNeedsDisplay()
    }

    func clearFrame() {
        renderer?.clear(on: self)
    }
}

/// SwiftUI wrapper — use only for Native backend surface (not AVPlayer).
struct MetalVideoView: UIViewRepresentable {
    var aspectMode: VideoAspectMode
    var frame: VideoFrame?

    func makeUIView(context: Context) -> MetalVideoUIView {
        let view = MetalVideoUIView(frame: .zero, device: nil)
        view.setAspectMode(aspectMode)
        return view
    }

    func updateUIView(_ uiView: MetalVideoUIView, context: Context) {
        uiView.setAspectMode(aspectMode)
        if let frame {
            uiView.present(frame)
        }
    }
}

/// Coordinator that pulls from `VideoFrameSink` on a display link cadence (optional host).
@MainActor
final class MetalDisplayLinkPump {
    private var displayLink: CADisplayLink?
    private weak var view: MetalVideoUIView?
    private let sink: VideoFrameSink
    private var lastCount = 0

    init(sink: VideoFrameSink) {
        self.sink = sink
    }

    func start(view: MetalVideoUIView) {
        self.view = view
        stop()
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick() {
        guard let view else { return }
        if sink.frameCount != lastCount, let frame = sink.latestFrame {
            lastCount = sink.frameCount
            view.present(frame)
        }
    }
}
