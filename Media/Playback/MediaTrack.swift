import Foundation

/// Contract-aligned track descriptor (docs/cross-platform-playback-contract.md §6).
/// UI and preference logic should prefer this over raw player track objects.
struct MediaTrack: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable, Hashable {
        case audio
        case subtitle
        case video
    }

    /// Stable within the current item session (usually Plex stream id as string).
    let id: String
    let type: Kind
    let language: String?
    let title: String?
    let codec: String?
    let isDefault: Bool
    var isSelected: Bool
    let isForced: Bool
    let isExternal: Bool
    /// Link back to Plex stream id when known.
    let plexStreamId: Int?

    static func fromPlexStream(_ stream: PlexStream, selectedId: Int?) -> MediaTrack {
        let kind: Kind
        switch stream.streamType {
        case .audio: kind = .audio
        case .subtitle: kind = .subtitle
        case .video: kind = .video
        default: kind = .audio
        }
        let title = stream.extendedDisplayTitle
            ?? stream.displayTitle
            ?? stream.title
            ?? stream.language
        return MediaTrack(
            id: String(stream.id),
            type: kind,
            language: stream.languageCode ?? stream.language,
            title: title,
            codec: stream.codec ?? stream.format,
            isDefault: stream.isDefault,
            isSelected: selectedId == stream.id,
            isForced: stream.isForced,
            isExternal: stream.isExternal,
            plexStreamId: stream.id
        )
    }
}

extension Array where Element == PlexStream {
    func asMediaTracks(selectedId: Int?) -> [MediaTrack] {
        map { MediaTrack.fromPlexStream($0, selectedId: selectedId) }
    }
}
