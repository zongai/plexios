using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using PlexWindows.Helpers;
using PlexWindows.Models;

namespace PlexWindows.Plex.Api;

/// <summary>
/// Windows implementation of the shared Plex API contract.
/// Mirrors iOS PlexAPIClient / PlexAPIProtocol semantics.
/// </summary>
public sealed class PlexApiClient
{
    private static readonly Uri PlexTvBase = new("https://plex.tv");
    private static readonly Uri ClientsPlexTvBase = new("https://clients.plex.tv");

    private readonly HttpClient _http;
    private readonly ClientIdentity _identity;
    private readonly JsonSerializerOptions _json;

    public PlexApiClient(HttpClient http, ClientIdentity identity)
    {
        _http = http;
        _identity = identity;
        _json = new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true,
            NumberHandling = JsonNumberHandling.AllowReadingFromString,
            Converters =
            {
                new FlexibleNullableDoubleConverter(),
                new FlexibleNullableIntConverter(),
                new FlexibleNullableLongConverter()
            }
        };
    }

    // MARK: - Auth

    public async Task<PlexPin> CreatePinAsync(CancellationToken ct = default)
    {
        using var req = new HttpRequestMessage(HttpMethod.Post, new Uri(ClientsPlexTvBase, "api/v2/pins"));
        _identity.ApplyTo(req);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var dto = await resp.Content.ReadFromJsonAsync<PinDto>(_json, ct).ConfigureAwait(false)
                  ?? throw new InvalidOperationException("Empty PIN response");
        return new PlexPin(dto.Id, dto.Code ?? "", dto.ExpiresIn, dto.AuthToken);
    }

    public async Task<PlexPin> CheckPinAsync(int id, string code, CancellationToken ct = default)
    {
        var url = new Uri(ClientsPlexTvBase, $"api/v2/pins/{id}?code={Uri.EscapeDataString(code)}");
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        _identity.ApplyTo(req);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var dto = await resp.Content.ReadFromJsonAsync<PinDto>(_json, ct).ConfigureAwait(false)
                  ?? throw new InvalidOperationException("Empty PIN poll response");
        return new PlexPin(dto.Id, dto.Code ?? code, dto.ExpiresIn, dto.AuthToken);
    }

    // MARK: - Discovery

    public async Task<IReadOnlyList<PlexServer>> FetchServersAsync(string authToken, CancellationToken ct = default)
    {
        var url = new Uri(PlexTvBase, "api/v2/resources?includeHttps=1&includeRelay=1&includeIPv6=1");
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        _identity.ApplyTo(req);
        req.Headers.TryAddWithoutValidation("X-Plex-Token", authToken);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var resources = await resp.Content.ReadFromJsonAsync<List<ResourceDto>>(_json, ct).ConfigureAwait(false)
                        ?? [];
        return resources
            .Where(r => r.Provides?.Contains("server", StringComparison.OrdinalIgnoreCase) == true)
            .Select(MapServer)
            .ToList();
    }

    // MARK: - Library / Home

    public async Task<IReadOnlyList<PlexLibrary>> FetchLibrarySectionsAsync(Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, "library/sections", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<DirectoryContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Directory ?? [])
            .Select(MapLibrary)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexHub>> FetchHomeHubsAsync(Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, "hubs", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<HubContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Hub ?? [])
            .Select(MapHub)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchLibraryAllAsync(
        string sectionKey, Uri baseUrl, string token, int start = 0, int size = 50, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"library/sections/{sectionKey}/all?X-Plex-Container-Start={start}&X-Plex-Container-Size={size}", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Metadata ?? [])
            .Select(MapMetadata)
            .ToList();
    }

    public async Task<PlexMetadata> FetchMetadataAsync(string ratingKey, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"library/metadata/{ratingKey}?includeMarkers=1&includeChildren=1", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        var item = container?.MediaContainer?.Metadata?.FirstOrDefault()
                   ?? throw new InvalidOperationException("Metadata not found");
        return MapMetadata(item);
    }

    public async Task<IReadOnlyList<PlexHub>> SearchAsync(string query, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"hubs/search?query={Uri.EscapeDataString(query)}", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<HubContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Hub ?? [])
            .Select(MapHub)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchChildrenAsync(
        string ratingKey, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"library/metadata/{ratingKey}/children", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Metadata ?? [])
            .Select(MapMetadata)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexHub>> FetchRelatedAsync(
        string ratingKey, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"library/metadata/{ratingKey}/related", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<HubContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Hub ?? [])
            .Select(MapHub)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchPlaylistsAsync(Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, "playlists", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Metadata ?? [])
            .Select(MapMetadata)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchCollectionsAsync(Uri baseUrl, string token, CancellationToken ct = default)
    {
        // Global collections path; some PMS builds 404 — caller may fall back to per-section.
        using var req = MakePmsRequest(baseUrl, "library/collections", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        if (!resp.IsSuccessStatusCode) return Array.Empty<PlexMetadata>();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Metadata ?? [])
            .Select(MapMetadata)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchSectionCollectionsAsync(
        string sectionKey, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"library/sections/{sectionKey}/collections", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        if (!resp.IsSuccessStatusCode) return Array.Empty<PlexMetadata>();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Metadata ?? [])
            .Select(MapMetadata)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchCollectionChildrenAsync(
        string ratingKey, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"library/collections/{ratingKey}/children", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        if (resp.IsSuccessStatusCode)
        {
            var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
                .ConfigureAwait(false);
            var items = (container?.MediaContainer?.Metadata ?? []).Select(MapMetadata).ToList();
            if (items.Count > 0) return items;
        }
        // Fallback to generic children
        return await FetchChildrenAsync(ratingKey, baseUrl, token, ct).ConfigureAwait(false);
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchPlaylistItemsAsync(
        string ratingKey, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $"playlists/{ratingKey}/items", token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Metadata ?? [])
            .Select(MapMetadata)
            .ToList();
    }

    public async Task<IReadOnlyList<PlexMetadata>> FetchFavoritesAsync(
        Uri baseUrl, string token, int start = 0, int size = 100, CancellationToken ct = default)
    {
        // PMS: items with userRating set (favorites use 10)
        using var req = MakePmsRequest(baseUrl,
            $"library/all?userRating>=1&X-Plex-Container-Start={start}&X-Plex-Container-Size={size}",
            token);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var container = await resp.Content.ReadFromJsonAsync<MediaContainerDto<MetadataContainerDto>>(_json, ct)
            .ConfigureAwait(false);
        return (container?.MediaContainer?.Metadata ?? [])
            .Select(MapMetadata)
            .ToList();
    }

    public async Task RateAsync(string key, int rating, Uri baseUrl, string token, CancellationToken ct = default)
    {
        using var req = MakePmsRequest(baseUrl, $":/rate?key={Uri.EscapeDataString(key)}&identifier=com.plexapp.plugins.library&rating={rating}", token);
        req.Method = HttpMethod.Put;
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
    }

    // MARK: - Helpers

    private HttpRequestMessage MakePmsRequest(Uri baseUrl, string pathAndQuery, string token)
    {
        var url = new Uri(baseUrl, pathAndQuery.TrimStart('/'));
        var req = new HttpRequestMessage(HttpMethod.Get, url);
        _identity.ApplyTo(req);
        req.Headers.TryAddWithoutValidation("X-Plex-Token", token);
        return req;
    }

    private static PlexServer MapServer(ResourceDto r)
    {
        var connections = (r.Connections ?? []).Select(c => new PlexConnection
        {
            Uri = c.Uri ?? "",
            Address = c.Address,
            Port = c.Port,
            ProtocolName = c.Protocol ?? "http",
            Local = c.Local ?? false,
            Relay = c.Relay ?? false,
            Ipv6 = c.IPv6 ?? false
        }).ToList();

        return new PlexServer
        {
            MachineIdentifier = r.ClientIdentifier ?? r.MachineIdentifier ?? "",
            Name = r.Name ?? "Plex Server",
            Product = r.Product,
            ProductVersion = r.ProductVersion,
            Platform = r.Platform,
            Owned = r.Owned ?? false,
            Home = r.Home ?? false,
            AccessToken = r.AccessToken ?? "",
            Connections = connections,
            PreferredConnection = connections.OrderBy(c => c.RankScore).FirstOrDefault()
        };
    }

    private static double? CoerceDouble(object? value)
    {
        if (value is null) return null;
        switch (value)
        {
            case double d: return d;
            case float f: return f;
            case int i: return i;
            case long l: return l;
            case decimal m: return (double)m;
            case JsonElement el:
                return el.ValueKind switch
                {
                    JsonValueKind.Number when el.TryGetDouble(out var d) => d,
                    JsonValueKind.String => double.TryParse(el.GetString(),
                        System.Globalization.NumberStyles.Float,
                        System.Globalization.CultureInfo.InvariantCulture, out var ds) ? ds : null,
                    _ => null
                };
            case string s when double.TryParse(s,
                System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var parsed):
                return parsed;
            default:
                return null;
        }
    }

    private static PlexLibrary MapLibrary(DirectoryDto d)
    {
        var type = d.Type?.ToLowerInvariant() switch
        {
            "movie" => PlexLibraryType.Movie,
            "show" => PlexLibraryType.Show,
            "artist" => PlexLibraryType.Artist,
            "photo" => PlexLibraryType.Photo,
            "mixed" => PlexLibraryType.Mixed,
            _ => PlexLibraryType.Unknown
        };
        return new PlexLibrary(d.Key ?? "", d.Uuid, d.Title ?? "", type, d.Agent, d.Scanner, d.Thumb, d.Art, d.Count, null);
    }

    private static PlexHub MapHub(HubDto h) => new()
    {
        Key = h.Key ?? "",
        HubIdentifier = h.HubIdentifier,
        Title = h.Title ?? "",
        Type = h.Type,
        Style = h.Style,
        Size = h.Size,
        More = h.More ?? false,
        Items = (h.Metadata ?? []).Select(MapMetadata).ToList()
    };

    private static PlexMetadata MapMetadata(MetadataDto m)
    {
        var type = Enum.TryParse<PlexMetadataType>(m.Type, ignoreCase: true, out var t)
            ? t : PlexMetadataType.Unknown;
        return new PlexMetadata
        {
            RatingKey = m.RatingKey ?? "",
            Key = m.Key ?? "",
            Type = type,
            Title = m.Title ?? "",
            Summary = m.Summary,
            Year = m.Year,
            ContentRating = m.ContentRating,
            Rating = CoerceDouble(m.Rating),
            AudienceRating = CoerceDouble(m.AudienceRating),
            UserRating = CoerceDouble(m.UserRating),
            Duration = m.Duration,
            ViewOffset = m.ViewOffset,
            ViewCount = m.ViewCount,
            Thumb = m.Thumb,
            Art = m.Art,
            ParentThumb = m.ParentThumb,
            GrandparentThumb = m.GrandparentThumb,
            ParentTitle = m.ParentTitle,
            GrandparentTitle = m.GrandparentTitle,
            ParentRatingKey = m.ParentRatingKey,
            GrandparentRatingKey = m.GrandparentRatingKey,
            Index = m.Index,
            ParentIndex = m.ParentIndex,
            LeafCount = m.LeafCount,
            ViewedLeafCount = m.ViewedLeafCount,
            ChildCount = m.ChildCount,
            Studio = m.Studio,
            Tagline = m.Tagline,
            Genres = m.Genre?.Select(g => g.Tag ?? "").Where(s => s.Length > 0).ToList() ?? [],
            Directors = m.Director?.Select(d => d.Tag ?? "").Where(s => s.Length > 0).ToList() ?? [],
            Media = (m.Media ?? []).Select(MapMedia).ToList()
        };
    }

    private static PlexMedia MapMedia(MediaDto m) => new()
    {
        Id = m.Id ?? 0,
        Duration = m.Duration,
        Bitrate = m.Bitrate,
        Width = m.Width,
        Height = m.Height,
        VideoCodec = m.VideoCodec,
        AudioCodec = m.AudioCodec,
        Container = m.Container,
        VideoResolution = m.VideoResolution,
        VideoFrameRate = m.VideoFrameRate,
        VideoProfile = m.VideoProfile,
        AudioChannels = m.AudioChannels,
        Parts = (m.Part ?? []).Select(MapPart).ToList()
    };

    private static PlexPart MapPart(PartDto p) => new()
    {
        Id = p.Id ?? 0,
        Key = p.Key ?? "",
        Duration = p.Duration,
        Size = p.Size,
        Container = p.Container,
        File = p.File,
        Accessible = p.Accessible,
        Streams = (p.Stream ?? []).Select(MapStream).ToList()
    };

    private static PlexStream MapStream(StreamDto s) => new()
    {
        Id = s.Id ?? 0,
        Type = (PlexStream.StreamType)(s.StreamType ?? 0),
        Codec = s.Codec,
        Format = s.Format,
        Language = s.Language,
        LanguageCode = s.LanguageCode,
        DisplayTitle = s.DisplayTitle,
        ExtendedDisplayTitle = s.ExtendedDisplayTitle,
        Title = s.Title,
        IsDefault = s.Default ?? false,
        IsForced = s.Forced ?? false,
        IsSelected = s.Selected ?? false,
        IsExternal = !string.IsNullOrEmpty(s.Key),
        Bitrate = s.Bitrate,
        Channels = s.Channels,
        Key = s.Key,
        BitDepth = s.BitDepth
    };

    // MARK: - DTOs (minimal, match Plex JSON)

    private sealed class PinDto
    {
        public int Id { get; set; }
        public string? Code { get; set; }
        public int? ExpiresIn { get; set; }
        public string? AuthToken { get; set; }
    }

    private sealed class ResourceDto
    {
        public string? Name { get; set; }
        public string? Product { get; set; }
        public string? ProductVersion { get; set; }
        public string? Platform { get; set; }
        public string? ClientIdentifier { get; set; }
        public string? MachineIdentifier { get; set; }
        public string? Provides { get; set; }
        public string? AccessToken { get; set; }
        public bool? Owned { get; set; }
        public bool? Home { get; set; }
        public List<ConnectionDto>? Connections { get; set; }
    }

    private sealed class ConnectionDto
    {
        public string? Protocol { get; set; }
        public string? Address { get; set; }
        public int? Port { get; set; }
        public string? Uri { get; set; }
        public bool? Local { get; set; }
        public bool? Relay { get; set; }
        public bool? IPv6 { get; set; }
    }

    private sealed class MediaContainerDto<T>
    {
        public T? MediaContainer { get; set; }
    }

    private sealed class DirectoryContainerDto
    {
        public List<DirectoryDto>? Directory { get; set; }
    }

    private sealed class DirectoryDto
    {
        public string? Key { get; set; }
        public string? Title { get; set; }
        public string? Type { get; set; }
        public string? Uuid { get; set; }
        public string? Agent { get; set; }
        public string? Scanner { get; set; }
        public string? Thumb { get; set; }
        public string? Art { get; set; }
        public int? Count { get; set; }
    }

    private sealed class HubContainerDto
    {
        public List<HubDto>? Hub { get; set; }
    }

    private sealed class HubDto
    {
        public string? Key { get; set; }
        public string? HubIdentifier { get; set; }
        public string? Title { get; set; }
        public string? Type { get; set; }
        public string? Style { get; set; }
        public int? Size { get; set; }
        public bool? More { get; set; }
        public List<MetadataDto>? Metadata { get; set; }
    }

    private sealed class MetadataContainerDto
    {
        public List<MetadataDto>? Metadata { get; set; }
    }

    private sealed class MetadataDto
    {
        public string? RatingKey { get; set; }
        public string? Key { get; set; }
        public string? Type { get; set; }
        public string? Title { get; set; }
        public string? Summary { get; set; }
        [JsonConverter(typeof(FlexibleNullableIntConverter))]
        public int? Year { get; set; }
        public string? ContentRating { get; set; }
        // Plex may emit number, string, empty, or odd tokens — keep as string and parse later
        public object? Rating { get; set; }
        public object? AudienceRating { get; set; }
        public object? UserRating { get; set; }
        [JsonConverter(typeof(FlexibleNullableLongConverter))]
        public long? Duration { get; set; }
        [JsonConverter(typeof(FlexibleNullableLongConverter))]
        public long? ViewOffset { get; set; }
        [JsonConverter(typeof(FlexibleNullableIntConverter))]
        public int? ViewCount { get; set; }
        public string? Thumb { get; set; }
        public string? Art { get; set; }
        public string? ParentThumb { get; set; }
        public string? GrandparentThumb { get; set; }
        public string? ParentTitle { get; set; }
        public string? GrandparentTitle { get; set; }
        public string? ParentRatingKey { get; set; }
        public string? GrandparentRatingKey { get; set; }
        [JsonConverter(typeof(FlexibleNullableIntConverter))]
        public int? Index { get; set; }
        [JsonConverter(typeof(FlexibleNullableIntConverter))]
        public int? ParentIndex { get; set; }
        [JsonConverter(typeof(FlexibleNullableIntConverter))]
        public int? LeafCount { get; set; }
        [JsonConverter(typeof(FlexibleNullableIntConverter))]
        public int? ViewedLeafCount { get; set; }
        [JsonConverter(typeof(FlexibleNullableIntConverter))]
        public int? ChildCount { get; set; }
        public string? Studio { get; set; }
        public string? Tagline { get; set; }
        public List<TagDto>? Genre { get; set; }
        public List<TagDto>? Director { get; set; }
        public List<MediaDto>? Media { get; set; }
    }

    private sealed class TagDto
    {
        public string? Tag { get; set; }
    }

    private sealed class MediaDto
    {
        public int? Id { get; set; }
        public long? Duration { get; set; }
        public int? Bitrate { get; set; }
        public int? Width { get; set; }
        public int? Height { get; set; }
        public string? VideoCodec { get; set; }
        public string? AudioCodec { get; set; }
        public string? Container { get; set; }
        public string? VideoResolution { get; set; }
        public string? VideoFrameRate { get; set; }
        public string? VideoProfile { get; set; }
        public int? AudioChannels { get; set; }
        public List<PartDto>? Part { get; set; }
    }

    private sealed class PartDto
    {
        public int? Id { get; set; }
        public string? Key { get; set; }
        public long? Duration { get; set; }
        public long? Size { get; set; }
        public string? Container { get; set; }
        public string? File { get; set; }
        public bool? Accessible { get; set; }
        public List<StreamDto>? Stream { get; set; }
    }

    private sealed class StreamDto
    {
        public int? Id { get; set; }
        public int? StreamType { get; set; }
        public string? Codec { get; set; }
        public string? Format { get; set; }
        public string? Language { get; set; }
        public string? LanguageCode { get; set; }
        public string? DisplayTitle { get; set; }
        public string? ExtendedDisplayTitle { get; set; }
        public string? Title { get; set; }
        public bool? Default { get; set; }
        public bool? Forced { get; set; }
        public bool? Selected { get; set; }
        public int? Bitrate { get; set; }
        public int? Channels { get; set; }
        public string? Key { get; set; }
        public int? BitDepth { get; set; }
    }
}
