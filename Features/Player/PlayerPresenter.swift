import SwiftUI

/// Lightweight helper to present PlayerView fullScreenCover from detail screens.
struct PlayerPresenter: ViewModifier {
    @Binding var item: PlexMetadata?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $item) { metadata in
                PlayerView(metadata: metadata)
            }
    }
}

extension View {
    func playerSheet(item: Binding<PlexMetadata?>) -> some View {
        modifier(PlayerPresenter(item: item))
    }
}
