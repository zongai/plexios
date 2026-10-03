using System.Net.Http;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;

namespace PlexWindows.Iptv;

/// <summary>File-backed IPTV store (playlists + channels). Aligns with iOS IPTVRepository subset.</summary>
public sealed class IptvRepository
{
    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private readonly string _root;
    private readonly HttpClient _http;
    private readonly object _gate = new();

    public IptvRepository(HttpClient http)
    {
        _http = http;
        _root = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PlexWindows", "iptv");
        Directory.CreateDirectory(_root);
    }

    private string PlaylistsPath => Path.Combine(_root, "playlists.json");
    private string ChannelsPath(Guid id) => Path.Combine(_root, $"channels-{id:N}.json");

    public List<IptvPlaylist> LoadPlaylists()
    {
        lock (_gate)
        {
            try
            {
                if (!File.Exists(PlaylistsPath)) return [];
                var json = File.ReadAllText(PlaylistsPath);
                return JsonSerializer.Deserialize<List<IptvPlaylist>>(json, JsonOpts) ?? [];
            }
            catch { return []; }
        }
    }

    public void SavePlaylists(List<IptvPlaylist> list)
    {
        lock (_gate)
        {
            File.WriteAllText(PlaylistsPath, JsonSerializer.Serialize(list, JsonOpts));
        }
    }

    public List<IptvChannel> LoadChannels(Guid playlistId)
    {
        lock (_gate)
        {
            try
            {
                var path = ChannelsPath(playlistId);
                if (!File.Exists(path)) return [];
                var json = File.ReadAllText(path);
                return JsonSerializer.Deserialize<List<IptvChannel>>(json, JsonOpts) ?? [];
            }
            catch { return []; }
        }
    }

    public void SaveChannels(Guid playlistId, List<IptvChannel> channels)
    {
        lock (_gate)
        {
            File.WriteAllText(ChannelsPath(playlistId), JsonSerializer.Serialize(channels, JsonOpts));
        }
    }

    public List<IptvChannel> AllEnabledChannels()
    {
        var list = new List<IptvChannel>();
        foreach (var pl in LoadPlaylists().Where(p => p.Enabled))
            list.AddRange(LoadChannels(pl.Id));
        return list;
    }

    public void AddPlaylist(IptvPlaylist playlist)
    {
        var list = LoadPlaylists();
        list.Add(playlist);
        SavePlaylists(list);
    }

    public void DeletePlaylist(Guid id)
    {
        var list = LoadPlaylists();
        list.RemoveAll(p => p.Id == id);
        SavePlaylists(list);
        try { File.Delete(ChannelsPath(id)); } catch { /* ignore */ }
    }

    public async Task<IptvPlaylist> RefreshPlaylistAsync(IptvPlaylist playlist, CancellationToken ct = default)
    {
        if (!Uri.TryCreate(playlist.Url, UriKind.Absolute, out var uri))
            throw new InvalidOperationException("Invalid playlist URL");

        using var req = new HttpRequestMessage(HttpMethod.Get, uri);
        req.Headers.TryAddWithoutValidation("User-Agent", "PlexWindows-IPTV/1.0");
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        resp.EnsureSuccessStatusCode();
        var bytes = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        var parsed = M3UParser.Parse(bytes);

        var channels = new List<IptvChannel>();
        foreach (var e in parsed.Entries)
        {
            var id = StableId(playlist.Id, e.TvgId, e.Name, e.StreamUrl);
            channels.Add(new IptvChannel
            {
                Id = id,
                Name = e.Name,
                LogoUrl = e.TvgLogo,
                Group = e.GroupTitle,
                TvgId = e.TvgId,
                StreamUrl = e.StreamUrl,
                PlaylistId = playlist.Id,
                Headers = e.Headers
            });
        }

        playlist.ChannelCount = channels.Count;
        playlist.LastUpdated = DateTimeOffset.UtcNow;
        if (!string.IsNullOrEmpty(parsed.EpgUrl))
            playlist.EpgUrl = parsed.EpgUrl;

        SaveChannels(playlist.Id, channels);
        var all = LoadPlaylists();
        var idx = all.FindIndex(p => p.Id == playlist.Id);
        if (idx >= 0) all[idx] = playlist;
        else all.Add(playlist);
        SavePlaylists(all);
        return playlist;
    }

    private static string StableId(Guid playlistId, string? tvgId, string name, string url)
    {
        var raw = $"{playlistId:N}|{tvgId}|{name}|{url}";
        var hash = SHA256.HashData(Encoding.UTF8.GetBytes(raw));
        return Convert.ToHexString(hash)[..16].ToLowerInvariant();
    }
}
