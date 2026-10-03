using CommunityToolkit.Mvvm.ComponentModel;
using PlexWindows.Models;
using PlexWindows.Playback;
using PlexWindows.Plex.Api;

namespace PlexWindows.Plex.Server;

/// <summary>
/// Discovers servers, ranks connections, maintains active server.
/// Matches iOS ConnectionManager semantics.
/// </summary>
public partial class ConnectionManager : ObservableObject
{
    private readonly PlexApiClient _api;

    [ObservableProperty] private IReadOnlyList<PlexServer> _servers = Array.Empty<PlexServer>();
    [ObservableProperty] private PlexServer? _activeServer;
    [ObservableProperty] private bool _isRefreshing;
    [ObservableProperty] private string? _lastError;

    public ConnectionManager(PlexApiClient api)
    {
        _api = api;
    }

    public Uri? ActiveBaseUrl => ActiveServer?.PreferredConnection?.BaseUrl;
    public string? ActiveToken => ActiveServer?.AccessToken;

    /// <summary>Derived from the preferred connection of the active server.</summary>
    public NetworkClass ActiveNetworkClass
    {
        get
        {
            var c = ActiveServer?.PreferredConnection;
            if (c is null) return NetworkClass.Unknown;
            if (c.Relay) return NetworkClass.Relay;
            if (c.Local) return NetworkClass.Local;
            return NetworkClass.Remote;
        }
    }

    public async Task DiscoverAsync(string authToken, CancellationToken ct = default)
    {
        IsRefreshing = true;
        LastError = null;
        try
        {
            var list = (await _api.FetchServersAsync(authToken, ct).ConfigureAwait(true)).ToList();
            foreach (var server in list)
            {
                server.PreferredConnection = server.Connections
                    .OrderBy(c => c.RankScore)
                    .ThenBy(c => c.LatencyMs ?? double.MaxValue)
                    .FirstOrDefault();
            }
            Servers = list;

            if (ActiveServer is { } current &&
                list.FirstOrDefault(s => s.MachineIdentifier == current.MachineIdentifier) is { } updated)
            {
                ActiveServer = updated;
            }
            else if (ActiveServer is null)
            {
                ActiveServer = list.FirstOrDefault(s => s.Owned) ?? list.FirstOrDefault();
            }
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
        }
        finally
        {
            IsRefreshing = false;
        }
    }

    public void SelectServer(PlexServer server)
    {
        ActiveServer = server;
        // Prefer best connection on that server
        if (server.PreferredConnection is null && server.Connections.Count > 0)
        {
            server.PreferredConnection = server.Connections
                .OrderBy(c => c.RankScore)
                .FirstOrDefault();
        }
        OnPropertyChanged(nameof(ActiveNetworkClass));
        OnPropertyChanged(nameof(ActiveBaseUrl));
        OnPropertyChanged(nameof(ActiveToken));
    }

    public void SelectConnection(PlexServer server, PlexConnection connection)
    {
        server.PreferredConnection = connection;
        ActiveServer = server;
        OnPropertyChanged(nameof(ActiveNetworkClass));
        OnPropertyChanged(nameof(ActiveBaseUrl));
        OnPropertyChanged(nameof(ActiveToken));
    }

    public void Reset()
    {
        Servers = Array.Empty<PlexServer>();
        ActiveServer = null;
        LastError = null;
    }

    /// <summary>
    /// Prefer plain HTTP LAN for LibVLC (plex.direct HTTPS is unreliable in VLC/gnutls).
    /// Order: explicit http local connection → synthesize http://IP from *.plex.direct → preferred.
    /// </summary>
    public Uri? PreferPlaybackBaseUrl(bool preferHttpLan = true)
    {
        var server = ActiveServer;
        if (server is null) return null;
        var preferred = server.PreferredConnection?.BaseUrl;

        if (preferHttpLan)
        {
            var httpLan = server.Connections
                .Where(c => c.BaseUrl is not null
                            && c.Local
                            && !c.Relay
                            && c.BaseUrl.Scheme.Equals("http", StringComparison.OrdinalIgnoreCase))
                .OrderBy(c => c.LatencyMs ?? double.MaxValue)
                .Select(c => c.BaseUrl!)
                .FirstOrDefault();
            if (httpLan is not null) return httpLan;

            // 192-168-1-10.xxxxx.plex.direct:32400 → http://192.168.1.10:32400
            foreach (var c in server.Connections.Select(x => x.BaseUrl).Where(u => u is not null))
            {
                var syn = TrySynthesizeLanHttp(c!);
                if (syn is not null) return syn;
            }
            if (preferred is not null)
            {
                var syn = TrySynthesizeLanHttp(preferred);
                if (syn is not null) return syn;
            }
        }
        return preferred;
    }

    /// <summary>
    /// Plex private.plex.direct hosts encode LAN IPs as dashed labels.
    /// </summary>
    public static Uri? TrySynthesizeLanHttp(Uri plexUri)
    {
        try
        {
            var host = plexUri.Host;
            if (!host.EndsWith(".plex.direct", StringComparison.OrdinalIgnoreCase))
                return null;
            var label = host.Split('.')[0]; // e.g. 192-168-1-10
            if (label.Count(c => c == '-') < 3) return null;
            var ip = label.Replace('-', '.');
            if (!System.Net.IPAddress.TryParse(ip, out _)) return null;
            var port = plexUri.IsDefaultPort ? 32400 : plexUri.Port;
            return new UriBuilder("http", ip, port).Uri;
        }
        catch
        {
            return null;
        }
    }
}
