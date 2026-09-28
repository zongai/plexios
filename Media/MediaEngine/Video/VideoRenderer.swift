import Foundation

/// Abstraction over Metal (and future) presenters.
protocol VideoRenderer: AnyObject {
    var aspectMode: VideoAspectMode { get set }
    func present(_ frame: VideoFrame)
    func clear()
}

extension MetalVideoRenderer {
    /// Bridge for protocol-style use with an attached MTKView.
    final class Presenter: VideoRenderer {
        let metal: MetalVideoRenderer
        weak var view: MetalVideoUIView?
        var aspectMode: VideoAspectMode {
            get { metal.aspectMode }
            set {
                metal.aspectMode = newValue
                view?.setNeedsDisplay()
            }
        }

        init(metal: MetalVideoRenderer, view: MetalVideoUIView?) {
            self.metal = metal
            self.view = view
        }

        func present(_ frame: VideoFrame) {
            metal.enqueue(frame, on: view)
        }

        func clear() {
            metal.clear(on: view)
        }
    }
}
