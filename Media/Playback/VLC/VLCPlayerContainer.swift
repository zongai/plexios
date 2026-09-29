import SwiftUI
import UIKit

/// Hosts the VLC drawable UIView inside SwiftUI.
/// Interaction is disabled so PlayerView overlay/controls receive taps.
struct VLCPlayerContainer: UIViewRepresentable {
    let backend: VLCPlaybackBackend
    var aspectMode: VideoAspectMode = .fit

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.isUserInteractionEnabled = false
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
        switch aspectMode {
        case .fit:
            backend.drawableView.contentMode = .scaleAspectFit
        case .fill:
            backend.drawableView.contentMode = .scaleAspectFill
        case .stretch:
            backend.drawableView.contentMode = .scaleToFill
        }
        // After rotation, force drawable to relayout (reduces glitches).
        uiView.setNeedsLayout()
        uiView.layoutIfNeeded()
        backend.drawableView.setNeedsLayout()
    }
}
