import SwiftUI
import UIKit

/// Hosts the VLC drawable UIView inside SwiftUI.
struct VLCPlayerContainer: UIViewRepresentable {
    let backend: VLCPlaybackBackend
    var aspectMode: VideoAspectMode = .fit

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        let drawable = backend.drawableView
        drawable.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(drawable)
        NSLayoutConstraint.activate([
            drawable.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            drawable.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            drawable.topAnchor.constraint(equalTo: container.topAnchor),
            drawable.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // VLC scales internally; aspect is best-effort via content mode on drawable.
        switch aspectMode {
        case .fit:
            backend.drawableView.contentMode = .scaleAspectFit
        case .fill:
            backend.drawableView.contentMode = .scaleAspectFill
        case .stretch:
            backend.drawableView.contentMode = .scaleToFill
        }
    }
}
