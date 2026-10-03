using System.Text.Json.Serialization;

namespace PlexWindows.Models;

// MARK: - Account / Auth

public sealed record PlexUser(
    string Id,
    string? Uuid,
    string? Username,
    string? Email,
    string? FriendlyName,
    Uri? Thumb,
    bool Home,
    bool Restricted);

public sealed record PlexPin(
    int Id,
    string Code,
    int? ExpiresIn,
    string? AuthToken);

// MARK: - Server & Connection

public sealed class PlexServer
{
    public string MachineIdentifier { get; init; } = "";
    public string Name { get; init; } = "";
    public string? Product { get; init; }
    public string? ProductVersion { get; init; }
    public string? Platform { get; init; }
    public bool Owned { get; init; }
    public bool Home { get; init; }
    public string AccessToken { get; init; } = "";
    public List<PlexConnection> Connections { get; init; } = [];
    public PlexConnection? PreferredConnection { get; set; }

    public string Id => MachineIdentifier;
}

public sealed class PlexConnection
{
    public string Uri { get; init; } = "";
    public string? Address { get; init; }
    public int? Port { get; init; }
    public string ProtocolName { get; init; } = "http"; // http | https
    public bool Local { get; init; }
    public bool Relay { get; init; }
    public bool Ipv6 { get; init; }
    public double? LatencyMs { get; set; }
    public DateTimeOffset? LastSuccess { get; set; }

    public string Id => Uri;
    public Uri? BaseUrl => System.Uri.TryCreate(Uri, UriKind.Absolute, out var u) ? u : null;

    /// <summary>Lower is better. Matches iOS rankScore semantics.</summary>
    public int RankScore
    {
        get
        {
            var score = 0;
            if (Relay) score += 1000;
            if (!Local) score += 100;
            if (Local)
            {
                if (ProtocolName == "https") score += 5;
            }
            else if (ProtocolName != "https")
            {
                score += 10;
            }
            if (Ipv6) score += 1;
            return score;
        }
    }
}

// MARK: - Library

public enum PlexLibraryType
{
    Movie, Show, Artist, Photo, Mixed, Unknown
}

public sealed record PlexLibrary(
    string Key,
    string? Uuid,
    string Title,
    PlexLibraryType Type,
    string? Agent,
    string? Scanner,
    string? Thumb,
    string? Art,
    int? Count,
    DateTimeOffset? UpdatedAt)
{
    public string Id => Key;
}

// MARK: - Hub

public sealed class PlexHub
{
    public string Key { get; init; } = "";
    public string? HubIdentifier { get; init; }
    public string Title { get; init; } = "";
    public string? Type { get; init; }
    public string? Style { get; init; }
    public int? Size { get; init; }
    public bool More { get; init; }
    public List<PlexMetadata> Items { get; set; } = [];

    public string Id => HubIdentifier ?? Key;
}

// MARK: - Metadata

public enum PlexMetadataType
{
    Movie, Show, Season, Episode, Artist, Album, Track,
    Collection, Playlist, Person, Clip, Photo, Trailer, Unknown
}


public enum PlexMarkerType
{
    Intro,
    Credits,
    Commercial,
    Unknown
}

/// <summary>Plex chapter-style marker (intro / credits). Offsets in milliseconds.</summary>
public sealed class PlexMarker
{
    public int Id { get; init; }
    public PlexMarkerType Type { get; init; }
    public long StartTimeOffset { get; init; }
    public long EndTimeOffset { get; init; }

    public bool Contains(long positionMs) =>
        positionMs >= StartTimeOffset && positionMs < EndTimeOffset && EndTimeOffset > StartTimeOffset;
}

public sealed class PlexMetadata
{
    public string RatingKey { get; init; } = "";
    public string Key { get; init; } = "";
    public PlexMetadataType Type { get; init; } = PlexMetadataType.Unknown;
    public string Title { get; init; } = "";
    public string? Summary { get; init; }
    public int? Year { get; init; }
    public string? ContentRating { get; init; }
    public double? Rating { get; init; }
    public double? AudienceRating { get; init; }
    public double? UserRating { get; init; }
    public long? Duration { get; init; }          // ms
    public long? ViewOffset { get; init; }        // ms
    public int? ViewCount { get; init; }
    public DateTimeOffset? LastViewedAt { get; init; }
    public string? OriginallyAvailableAt { get; init; }
    public string? Thumb { get; init; }
    public string? Art { get; init; }
    public string? ParentThumb { get; init; }
    public string? GrandparentThumb { get; init; }
    public string? ParentTitle { get; init; }
    public string? GrandparentTitle { get; init; }
    public string? ParentRatingKey { get; init; }
    public string? GrandparentRatingKey { get; init; }
    public int? Index { get; init; }
    public int? ParentIndex { get; init; }
    public string? LibrarySectionId { get; init; }
    public string? LibrarySectionTitle { get; init; }
    public int? LeafCount { get; init; }
    public int? ViewedLeafCount { get; init; }
    public int? ChildCount { get; init; }
    public string? Studio { get; init; }
    public string? Tagline { get; init; }
    public List<string> Genres { get; init; } = [];
    public List<string> Directors { get; init; } = [];
    public List<string> Writers { get; init; } = [];
    public List<PlexRole> Actors { get; init; } = [];
    public List<PlexMedia> Media { get; init; } = [];
    public List<PlexMarker> Markers { get; init; } = [];

    public string Id => RatingKey;

    public bool IsInProgress
    {
        get
        {
            if (ViewOffset is not > 0 || Duration is not > 0) return false;
            return (double)ViewOffset.Value / Duration.Value < 0.95;
        }
    }

    public bool IsWatched => (ViewCount ?? 0) > 0 && !IsInProgress;

    public double ProgressFraction
    {
        get
        {
            if (ViewOffset is null || Duration is not > 0) return 0;
            return Math.Min(1.0, (double)ViewOffset.Value / Duration.Value);
        }
    }

    public bool IsFavorite => (UserRating ?? 0) >= 1;
}

public sealed record PlexRole(string Tag, string? Role, string? Thumb);

// MARK: - Media hierarchy

public sealed class PlexMedia
{
    public int Id { get; init; }
    public long? Duration { get; init; }
    public int? Bitrate { get; init; }
    public int? Width { get; init; }
    public int? Height { get; init; }
    public string? VideoCodec { get; init; }
    public string? AudioCodec { get; init; }
    public string? Container { get; init; }
    public string? VideoResolution { get; init; }
    public string? VideoFrameRate { get; init; }
    public string? VideoProfile { get; init; }
    public int? AudioChannels { get; init; }
    public List<PlexPart> Parts { get; init; } = [];
}

public sealed class PlexPart
{
    public int Id { get; init; }
    public string Key { get; init; } = "";
    public long? Duration { get; init; }
    public long? Size { get; init; }
    public string? Container { get; init; }
    public string? File { get; init; }
    public bool? Accessible { get; init; }
    public List<PlexStream> Streams { get; init; } = [];
}

public sealed class PlexStream
{
    public int Id { get; init; }
    public StreamType Type { get; init; }
    public string? Codec { get; init; }
    public string? Format { get; init; }
    public string? Language { get; init; }
    public string? LanguageCode { get; init; }
    public string? DisplayTitle { get; init; }
    public string? ExtendedDisplayTitle { get; init; }
    public string? Title { get; init; }
    public bool IsDefault { get; init; }
    public bool IsForced { get; init; }
    public bool IsSelected { get; init; }
    public bool IsExternal { get; init; }
    public int? Bitrate { get; init; }
    public int? Channels { get; init; }
    public string? Key { get; init; }
    public int? BitDepth { get; init; }

    public enum StreamType
    {
        Unknown = 0,
        Video = 1,
        Audio = 2,
        Subtitle = 3
    }
}

// MARK: - Server context for PMS calls

public sealed record ServerContext(
    Uri BaseUrl,
    string Token,
    string MachineIdentifier);
