import AVFoundation
import AVKit
import SwiftUI

/// AVPlayerLayer host that supports Picture in Picture and aspect modes.
struct PlayerLayerView: UIViewControllerRepresentable {
    let player: AVPlayer
    var aspectMode: VideoAspectMode = .fit
    var onPiPActiveChange: ((Bool) -> Void)?

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = false
        controller.delegate = context.coordinator
        controller.showsPlaybackControls = false
        // Ensure closed captions / subtitle layers are shown when selected
        controller.allowsVideoFrameAnalysis = false
        applyGravity(controller, mode: aspectMode)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        applyGravity(controller, mode: aspectMode)
        context.coordinator.onPiPActiveChange = onPiPActiveChange
    }

    private func applyGravity(_ controller: AVPlayerViewController, mode: VideoAspectMode) {
        switch mode {
        case .fit:
            controller.videoGravity = .resizeAspect
        case .fill:
            controller.videoGravity = .resizeAspectFill
        case .stretch:
            controller.videoGravity = .resize
        }
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
