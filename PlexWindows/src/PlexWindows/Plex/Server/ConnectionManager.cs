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
}
