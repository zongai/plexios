import SwiftUI

#if canImport(SwiftVLC)
import SwiftVLC
#endif

/// Hosts SwiftVLC `VideoView(player)` for Direct Play.
///
/// Phase 2: thin wrapper so `PlayerView` can swap `VLCPlayerContainer` → this
/// without restructuring layout. Aspect mode is applied on the backend
/// (`Player.aspectRatio`); frame fit/fill can still be refined later.
struct SwiftVLCPlayerContainer: View {
    let backend: SwiftVLCPlaybackBackend
    var aspectMode: VideoAspectMode = .fit

    var body: some View {
        Group {
#if canImport(SwiftVLC)
            if let player = backend.player {
                VideoView(player)
                    .background(Color.black)
            } else {
                Color.black
            }
#else
            Color.black
#endif
        }
        .onAppear {
            backend.setAspectMode(aspectMode)
        }
        .onChange(of: aspectMode) { _, newValue in
            backend.setAspectMode(newValue)
        }
    }
}
