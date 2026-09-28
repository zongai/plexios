import Foundation

enum PlexAPIMapper {
    // MARK: - Auth

    static func pin(from dto: APIPINResponse) -> PlexPin {
        PlexPin(
            id: dto.id,
            code: dto.code,
            expiresIn: dto.expiresIn,
            authToken: dto.authToken
        )
    }

    // MARK: - Server

    static func server(from resource: APIResource) -> PlexServer? {
        guard resource.isServer,
              let token = resource.accessToken,
              !token.isEmpty,
              let machineId = resource.clientIdentifier,
              !machineId.isEmpty
        else { return nil }

        let connections = (resource.connections ?? []).compactMap(connection(from:))
        return PlexServer(
            machineIdentifier: machineId,
            name: resource.name ?? "Plex Server",
            product: resource.product,
            productVersion: resource.productVersion,
            platform: resource.platform,
            owned: resource.owned ?? false,
            home: resource.home ?? false,
            accessToken: token,
            connections: connections,
            preferredConnection: connections.sorted { $0.rankScore < $1.rankScore }.first
        )
    }

    static func connection(from dto: APIConnection) -> PlexConnection? {
        guard let uri = dto.uri, !uri.isEmpty else { return nil }
        return PlexConnection(
            uri: uri,
            address: dto.address,
            port: dto.port,
            protocolName: dto.protocolName ?? "https",
            local: dto.local ?? false,
            relay: dto.relay ?? false,
            ipv6: dto.ipv6 ?? false,
            latencyMs: nil,
            lastSuccess: nil
        )
    }

    // MARK: - Library

    static func library(from dto: APIDirectory) -> PlexLibrary? {
        guard let key = dto.key, let title = dto.title else { return nil }
        return PlexLibrary(
            key: key,
            uuid: dto.uuid,
            title: title,
            type: PlexLibraryType(plexType: dto.type),
            agent: dto.agent,
            scanner: dto.scanner,
            thumb: dto.thumb,
            art: dto.art,
            count: dto.count,
            updatedAt: dto.updatedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }

    // MARK: - Hub

    static func hub(from dto: APIHub) -> PlexHub? {
        guard let key = dto.key ?? dto.hubKey, let title = dto.title else { return nil }
        return PlexHub(
            key: key,
            hubIdentifier: dto.hubIdentifier,
            title: title,
            type: dto.type,
            style: dto.style,
            size: dto.size,
            more: dto.more ?? false,
            items: (dto.metadata ?? []).compactMap(metadata(from:))
        )
    }

    // MARK: - Metadata

    static func metadata(from dto: APIMetadata) -> PlexMetadata? {
        guard let ratingKey = dto.ratingKey,
              let key = dto.key,
              let title = dto.title
        else { return nil }

        return PlexMetadata(
            ratingKey: ratingKey,
            key: key,
            type: PlexMetadataType(raw: dto.type),
            title: title,
            summary: dto.summary,
            year: dto.year,
            contentRating: dto.contentRating,
            rating: dto.rating,
            audienceRating: dto.audienceRating,
            userRating: dto.userRating,
            duration: dto.duration,
            viewOffset: dto.viewOffset,
            viewCount: dto.viewCount,
            lastViewedAt: dto.lastViewedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            originallyAvailableAt: dto.originallyAvailableAt,
            thumb: dto.thumb,
            art: dto.art,
            parentThumb: dto.parentThumb,
            grandparentThumb: dto.grandparentThumb,
            parentTitle: dto.parentTitle,
            grandparentTitle: dto.grandparentTitle,
            parentRatingKey: dto.parentRatingKey,
            grandparentRatingKey: dto.grandparentRatingKey,
            index: dto.index,
            parentIndex: dto.parentIndex,
            leafCount: dto.leafCount,
            viewedLeafCount: dto.viewedLeafCount,
            childCount: dto.childCount,
            studio: dto.studio,
            tagline: dto.tagline,
            genres: (dto.genre ?? []).compactMap(\.tag),
            directors: (dto.director ?? []).compactMap(\.tag),
            writers: (dto.writer ?? []).compactMap(\.tag),
            actors: (dto.role ?? []).compactMap { role in
                guard let tag = role.tag else { return nil }
                return PlexRole(tag: tag, role: role.role, thumb: role.thumb)
            },
            media: (dto.media ?? []).compactMap(media(from:))
        )
    }

    static func media(from dto: APIMedia) -> PlexMedia? {
        guard let id = dto.id else { return nil }
        return PlexMedia(
            id: id,
            duration: dto.duration,
            bitrate: dto.bitrate,
            width: dto.width,
            height: dto.height,
            videoCodec: dto.videoCodec,
            audioCodec: dto.audioCodec,
            container: dto.container,
            videoResolution: dto.videoResolution,
            videoFrameRate: dto.videoFrameRate,
            videoProfile: dto.videoProfile,
            audioChannels: dto.audioChannels,
            parts: (dto.part ?? []).compactMap(part(from:))
        )
    }

    static func part(from dto: APIPart) -> PlexPart? {
        guard let id = dto.id, let key = dto.key else { return nil }
        return PlexPart(
            id: id,
            key: key,
            duration: dto.duration,
            size: dto.size,
            container: dto.container,
            file: dto.file,
            accessible: dto.accessible,
            streams: (dto.stream ?? []).compactMap(stream(from:))
        )
    }

    static func stream(from dto: APIStream) -> PlexStream? {
        guard let id = dto.id else { return nil }
        let type = PlexStream.StreamType(rawValue: dto.streamType ?? 0) ?? .unknown
        return PlexStream(
            id: id,
            streamType: type,
            codec: dto.codec,
            format: dto.format,
            language: dto.language,
            languageCode: dto.languageCode,
            displayTitle: dto.displayTitle,
            extendedDisplayTitle: dto.extendedDisplayTitle,
            title: dto.title,
            isDefault: dto.isDefault ?? dto.default ?? false,
            isForced: dto.forced ?? false,
            isSelected: dto.selected ?? false,
            isExternal: dto.external ?? false,
            bitrate: dto.bitrate,
            channels: dto.channels,
            key: dto.key,
            bitDepth: dto.bitDepth
        )
    }
}
