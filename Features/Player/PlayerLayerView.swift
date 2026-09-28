import AVFoundation
import AVKit
import SwiftUI

/// AVPlayerLayer host that supports Picture in Picture.
struct PlayerLayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var onPiPActiveChange: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false // we manage Now Playing ourselves
        controller.delegate = context.coordinator
        // Show transport only when we want system chrome; we use custom controls primarily.
        controller.showsPlaybackControls = false
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        context.coordinator.onPiPActiveChange = onPiPActiveChange
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPiPActiveChange: onPiPActiveChange)
    }

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        var onPiPActiveChange: ((Bool) -> Void)?

        init(onPiPActiveChange: ((Bool) -> Void)?) {
            self.onPiPActiveChange = onPiPActiveChange
        }

        func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
            onPiPActiveChange?(true)
        }

        func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
            onPiPActiveChange?(false)
        }

        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            // Host view is still in hierarchy when using fullScreenCover; allow restore.
            completionHandler(true)
        }
    }
}

/// System AirPlay route picker button.
struct AirPlayRoutePickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = .systemBlue
        view.prioritizesVideoDevices = true
        return view
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
