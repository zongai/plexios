import SwiftUI
import UIKit

/// Hosts the VLC drawable UIView and applies aspect modes by **sizing the drawable**.
/// Fit / fill / stretch do not depend on MobileVLCKit videoAspectRatio APIs.
struct VLCPlayerContainer: UIViewRepresentable {
    let backend: VLCPlaybackBackend
    var aspectMode: VideoAspectMode = .fit

    func makeCoordinator() -> Coordinator {
        Coordinator(backend: backend)
    }

    final class Coordinator: NSObject {
        let backend: VLCPlaybackBackend
        weak var container: AspectContainerView?
        private var link: CADisplayLink?
        private var ticks = 0
        private var sawVideoSize = false

        init(backend: VLCPlaybackBackend) {
            self.backend = backend
            super.init()
        }

        func startSizePolling() {
            stopSizePolling()
            ticks = 0
            sawVideoSize = backend.currentVideoSize.width > 1
            let link = CADisplayLink(target: self, selector: #selector(tick))
            // ~10 Hz is enough to catch video size.
            if #available(iOS 15.0, *) {
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 5, maximum: 15, preferred: 10)
            }
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stopSizePolling() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick() {
            ticks += 1
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hasSize = self.backend.currentVideoSize.width > 1
                if hasSize, !self.sawVideoSize {
                    self.sawVideoSize = true
                    self.container?.reapply(forceRebind: true)
                } else {
                    self.container?.reapply(forceRebind: false)
                }
                if self.ticks > 40 || (self.sawVideoSize && self.ticks > 15) {
                    self.stopSizePolling()
                }
            }
        }

        deinit {
            link?.invalidate()
        }
    }

    func makeUIView(context: Context) -> UIView {
        let container = AspectContainerView()
        container.backgroundColor = .black
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        container.backend = backend

        let drawable = backend.drawableView
        drawable.isUserInteractionEnabled = false
        drawable.backgroundColor = .black
        drawable.translatesAutoresizingMaskIntoConstraints = true
        drawable.autoresizingMask = []
        if drawable.superview !== container {
            drawable.removeFromSuperview()
            container.addSubview(drawable)
        }
        container.drawable = drawable
        context.coordinator.container = container
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let container = uiView as? AspectContainerView else { return }
        container.clipsToBounds = true
        container.backend = backend
        container.mode = aspectMode
        if backend.drawableView.superview !== container {
            backend.drawableView.removeFromSuperview()
            container.addSubview(backend.drawableView)
        }
        container.drawable = backend.drawableView

        let size = container.bounds.size
        if size.width > 32, size.height > 32 {
            if abs(container.lastBoundSize.width - size.width) > 8
                || abs(container.lastBoundSize.height - size.height) > 8 {
                container.lastBoundSize = size
                backend.rebindDrawable()
            }
        }

        backend.setAspectMode(aspectMode)
        container.reapply(forceRebind: true)
        context.coordinator.startSizePolling()
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stopSizePolling()
    }
}

/// Positions the VLC drawable for fit / fill / stretch using frames.
final class AspectContainerView: UIView {
    weak var drawable: UIView?
    weak var backend: VLCPlaybackBackend?
    var mode: VideoAspectMode = .fit
    var lastBoundSize: CGSize = .zero
    private var lastAppliedFrame: CGRect = .null

    func reapply(forceRebind: Bool) {
        let boundsSize = bounds.size
        guard let drawable, boundsSize.width > 1, boundsSize.height > 1 else { return }

        drawable.transform = .identity

        let videoSize = backend?.currentVideoSize ?? .zero
        let hasVideo = videoSize.width > 1 && videoSize.height > 1
        let vW = hasVideo ? videoSize.width : 16
        let vH = hasVideo ? videoSize.height : 9
        let videoAspect = vW / max(vH, 0.001)
        let viewAspect = boundsSize.width / max(boundsSize.height, 0.001)

        let frame: CGRect
        switch mode {
        case .fit:
            if videoAspect > viewAspect {
                let h = boundsSize.width / videoAspect
                frame = CGRect(x: 0, y: (boundsSize.height - h) / 2, width: boundsSize.width, height: h)
            } else {
                let w = boundsSize.height * videoAspect
                frame = CGRect(x: (boundsSize.width - w) / 2, y: 0, width: w, height: boundsSize.height)
            }
        case .fill:
            if videoAspect > viewAspect {
                let w = boundsSize.height * videoAspect
                frame = CGRect(x: (boundsSize.width - w) / 2, y: 0, width: w, height: boundsSize.height)
            } else {
                let h = boundsSize.width / videoAspect
                frame = CGRect(x: 0, y: (boundsSize.height - h) / 2, width: boundsSize.width, height: h)
            }
        case .stretch:
            frame = CGRect(origin: .zero, size: boundsSize)
        }

        let frameChanged = lastAppliedFrame.isNull
            || abs(lastAppliedFrame.width - frame.width) > 1
            || abs(lastAppliedFrame.height - frame.height) > 1
            || abs(lastAppliedFrame.minX - frame.minX) > 1
            || abs(lastAppliedFrame.minY - frame.minY) > 1

        guard frameChanged || forceRebind else { return }

        lastAppliedFrame = frame
        drawable.frame = frame
        drawable.setNeedsLayout()
        drawable.layoutIfNeeded()
        if forceRebind || frameChanged {
            backend?.rebindDrawablePreservingAspect()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        reapply(forceRebind: false)
    }
}
