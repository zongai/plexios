import SwiftUI
import UIKit

/// Hosts the VLC drawable UIView inside SwiftUI.
/// Interaction is disabled so PlayerView overlay/controls receive taps.
struct VLCPlayerContainer: UIViewRepresentable {
    let backend: VLCPlaybackBackend
    var aspectMode: VideoAspectMode = .fit

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastSize: CGSize = .zero
        var lastAspect: VideoAspectMode?
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        let drawable = backend.drawableView
        drawable.isUserInteractionEnabled = false
        drawable.translatesAutoresizingMaskIntoConstraints = false
        if drawable.superview !== container {
            drawable.removeFromSuperview()
            container.addSubview(drawable)
            NSLayoutConstraint.activate([
                drawable.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                drawable.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                drawable.topAnchor.constraint(equalTo: container.topAnchor),
                drawable.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.clipsToBounds = true
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        backend.drawableView.setNeedsLayout()
        backend.drawableView.layoutIfNeeded()

        let size = uiView.bounds.size
        let aspectChanged = context.coordinator.lastAspect != aspectMode
        var sizeChanged = false
        if size.width > 32, size.height > 32 {
            let prev = context.coordinator.lastSize
            sizeChanged = abs(prev.width - size.width) > 8 || abs(prev.height - size.height) > 8
            if sizeChanged {
                context.coordinator.lastSize = size
                backend.rebindDrawable()
            }
        }

        if aspectChanged || sizeChanged {
            context.coordinator.lastAspect = aspectMode
            backend.setAspectMode(aspectMode)
        }
    }
}
