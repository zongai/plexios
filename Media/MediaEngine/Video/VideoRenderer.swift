import Foundation
import MetalKit

/// Abstraction over Metal (and future) presenters.
protocol VideoRenderer: AnyObject {
    var aspectMode: VideoAspectMode { get set }
    func present(_ frame: VideoFrame)
    func clear()
}

extension MetalVideoRenderer {
    /// Shared bridge: Pipeline presents frames here; PlayerView attaches the MTKView.
    final class Presenter: VideoRenderer, @unchecked Sendable {
        let metal: MetalVideoRenderer
        private let lock = NSLock()
        private weak var view: MetalVideoUIView?
        private var lastFrame: VideoFrame?

        var aspectMode: VideoAspectMode {
            get { metal.aspectMode }
            set {
                metal.aspectMode = newValue
                lock.lock()
                let v = view
                lock.unlock()
                DispatchQueue.main.async { v?.setNeedsDisplay() }
            }
        }

        init(metal: MetalVideoRenderer) {
            self.metal = metal
        }

        /// Called from UI when MetalVideoUIView is ready.
        func attach(view: MetalVideoUIView) {
            lock.lock()
            self.view = view
            let pending = lastFrame
            lock.unlock()
            metal.attach(to: view)
            view.rendererBridge = self
            if let pending {
                metal.enqueue(pending, on: view)
            }
        }

        func detach() {
            lock.lock()
            view = nil
            lock.unlock()
        }

        func present(_ frame: VideoFrame) {
            lock.lock()
            lastFrame = frame
            let v = view
            lock.unlock()
            metal.enqueue(frame, on: v)
            // Always feed sink consumers via pixel buffer held in renderer
        }

        func clear() {
            lock.lock()
            lastFrame = nil
            let v = view
            lock.unlock()
            metal.clear(on: v)
        }
    }
}
