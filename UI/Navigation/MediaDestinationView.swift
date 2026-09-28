import SwiftUI

/// Resolves MediaRoute → concrete detail views.
struct MediaDestinationView: View {
    let route: MediaRoute

    var body: some View {
        switch route {
        case .movie(let key):
            MovieDetailView(ratingKey: key)
        case .show(let key):
            ShowDetailView(ratingKey: key)
        case .season(let key, let showTitle):
            SeasonDetailView(ratingKey: key, showTitle: showTitle)
        case .episode(let key):
            EpisodeDetailView(ratingKey: key)
        }
    }
}
