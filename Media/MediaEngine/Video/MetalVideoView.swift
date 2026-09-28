import MetalKit
import SwiftUI

/// UIKit host for Metal video output (Native Media Engine).
final class MetalVideoUIView: MTKView {
    /// Local renderer if no shared presenter is supplied.
    private let localRenderer: MetalVideoRenderer?
    /// Shared presenter from PlaybackPipeline (preferred).
    var rendererBridge: MetalVideoRenderer.Presenter?

    private var displayLink: CADisplayLink?
    private weak var boundSink: VideoFrameSink?
    private var lastFrameCount = -1

    var activeRenderer: MetalVideoRenderer? {
        rendererBridge?.metal ?? localRenderer
    }

    override init(frame: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        self.localRenderer = MetalVideoRenderer(device: metalDevice)
        super.init(frame: frame, device: metalDevice)
        isOpaque = true
        backgroundColor = .black
        enableSetNeedsDisplay = true
        isPaused = true
        if let localRenderer {
            localRenderer.attach(to: self)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
        rendererBridge?.detach()
    }

    func present(_ frame: VideoFrame) {
        if let bridge = rendererBridge {
            bridge.present(frame)
        } else {
            localRenderer?.enqueue(frame, on: self)
        }
    }

    func setAspectMode(_ mode: VideoAspectMode) {
        if let bridge = rendererBridge {
            bridge.aspectMode = mode
        } else {
            localRenderer?.aspectMode = mode
            setNeedsDisplay()
        }
    }

    func clearFrame() {
        if let bridge = rendererBridge {
            bridge.clear()
        } else {
            localRenderer?.clear(on: self)
        }
    }

    /// Bind pipeline sink (fallback path) and/or shared presenter.
    func bind(sink: VideoFrameSink?, presenter: MetalVideoRenderer.Presenter?) {
        if let presenter {
            presenter.attach(view: self)
            rendererBridge = presenter
        }
        boundSink = sink
        lastFrameCount = -1
        displayLink?.invalidate()
        // DisplayLink only needed when driving from sink without presenter draws
        guard sink != nil, presenter == nil else { return }
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

/// SwiftUI wrapper — prefers shared `MetalVideoRenderer.Presenter` from Native pipeline.
struct MetalVideoView: UIViewRepresentable {
    var aspectMode: VideoAspectMode
    var sink: VideoFrameSink?
    var presenter: MetalVideoRenderer.Presenter?
    var frame: VideoFrame?

    func makeUIView(context: Context) -> MetalVideoUIView {
        let view = MetalVideoUIView(frame: .zero, device: nil)
        view.bind(sink: sink, presenter: presenter)
        view.setAspectMode(aspectMode)
        if let frame {
            view.present(frame)
        }
        return view
    }

    func updateUIView(_ uiView: MetalVideoUIView, context: Context) {
        uiView.bind(sink: sink, presenter: presenter)
        uiView.setAspectMode(aspectMode)
        if let frame {
            uiView.present(frame)
        }
    }

    static func dismantleUIView(_ uiView: MetalVideoUIView, coordinator: ()) {
        uiView.bind(sink: nil, presenter: nil)
        uiView.clearFrame()
    }
}
