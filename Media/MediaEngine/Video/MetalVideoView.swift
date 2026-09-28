import MetalKit
import SwiftUI

/// UIKit host for Metal video output (Native Media Engine).
final class MetalVideoUIView: MTKView {
    let renderer: MetalVideoRenderer?
    private var displayLink: CADisplayLink?
    private weak var boundSink: VideoFrameSink?
    private var lastFrameCount = -1

    override init(frame: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        self.renderer = MetalVideoRenderer(device: metalDevice)
        super.init(frame: frame, device: metalDevice)
        isOpaque = true
        backgroundColor = .black
        enableSetNeedsDisplay = true
        isPaused = true
        if let renderer {
            renderer.attach(to: self)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
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

    func bind(sink: VideoFrameSink?) {
        boundSink = sink
        lastFrameCount = -1
        displayLink?.invalidate()
        guard sink != nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        guard let sink = boundSink else { return }
        if sink.frameCount != lastFrameCount, let frame = sink.latestFrame {
            lastFrameCount = sink.frameCount
            present(frame)
        }
    }
}

/// SwiftUI wrapper for Native backend — pulls frames from `VideoFrameSink`.
struct MetalVideoView: UIViewRepresentable {
    var aspectMode: VideoAspectMode
    var sink: VideoFrameSink?
    var frame: VideoFrame?

    func makeUIView(context: Context) -> MetalVideoUIView {
        let view = MetalVideoUIView(frame: .zero, device: nil)
        view.setAspectMode(aspectMode)
        view.bind(sink: sink)
        if let frame {
            view.present(frame)
        }
        return view
    }

    func updateUIView(_ uiView: MetalVideoUIView, context: Context) {
        uiView.setAspectMode(aspectMode)
        uiView.bind(sink: sink)
        if let frame {
            uiView.present(frame)
        }
    }

    static func dismantleUIView(_ uiView: MetalVideoUIView, coordinator: ()) {
        uiView.bind(sink: nil)
        uiView.clearFrame()
    }
}
