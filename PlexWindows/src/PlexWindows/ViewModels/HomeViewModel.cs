using CommunityToolkit.Mvvm.ComponentModel;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Auth;
using PlexWindows.Plex.Server;
using PlexWindows.Services;

namespace PlexWindows.ViewModels;

public sealed class HubCards
{
    public required string Title { get; init; }
    public required IReadOnlyList<MediaCardItem> Items { get; init; }
}

public partial class HomeViewModel : ObservableObject
{
    private readonly PlexApiClient _api;
    private readonly AuthenticationService _auth;
    private readonly ConnectionManager _connections;
    private readonly AppSettings _settings;
    private IReadOnlyList<PlexHub> _rawHubs = Array.Empty<PlexHub>();

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private IReadOnlyList<HubCards> _hubs = Array.Empty<HubCards>();

    public HomeViewModel(PlexApiClient api, AuthenticationService auth, ConnectionManager connections, AppSettings settings)
    {
        _api = api;
        _auth = auth;
        _connections = connections;
        _settings = settings;
        // If shell discovers a server after this page was constructed, reload
        _connections.PropertyChanged += async (_, e) =>
        {
            if (e.PropertyName == nameof(ConnectionManager.ActiveServer) &&
                _connections.ActiveServer is not null)
            {
                await LoadAsync();
            }
        };
    }

    public async Task LoadAsync()
    {
        if (_connections.ActiveBaseUrl is null || string.IsNullOrEmpty(_connections.ActiveToken) ||
            _connections.ActiveServer is null)
        {
            StatusMessage = string.IsNullOrEmpty(_auth.AuthToken)
                ? "Not signed in."
                : "Discovering server… (or open Servers to pick one)";
            return;
        }

        IsLoading = true;
        StatusMessage = "Loading hubs…";
        try
        {
            var ctx = new ServerContext(
                _connections.ActiveBaseUrl,
                _connections.ActiveToken,
                _connections.ActiveServer.MachineIdentifier);

            var hubs = await _api.FetchHomeHubsAsync(ctx.BaseUrl, ctx.Token);
            _rawHubs = hubs;
            IReadOnlyList<PlexLibrary> libraries = Array.Empty<PlexLibrary>();
            try
            {
                libraries = await _api.FetchLibrarySectionsAsync(ctx.BaseUrl, ctx.Token);
            }
            catch { /* optional for filter */ }
            ApplyHomeFilter(ctx, libraries);
            StatusMessage = Hubs.Count == 0 ? "No hubs returned from this server." : "";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Failed to load home: {ex.Message}";
        }
        finally
        {
            IsLoading = false;
        }
    }

    public void ApplyHomeFilter(ServerContext? ctx = null, IReadOnlyList<PlexLibrary>? libraries = null)
    {
        ctx ??= _connections.ActiveBaseUrl is not null
                && !string.IsNullOrEmpty(_connections.ActiveToken)
                && _connections.ActiveServer is not null
            ? new ServerContext(_connections.ActiveBaseUrl, _connections.ActiveToken,
                _connections.ActiveServer.MachineIdentifier)
            : null;

        var prefs = _settings.HomeDisplay;
        var filtered = prefs.Filter(_rawHubs.ToList(), libraries);
        Hubs = filtered.Select(h => new HubCards
        {
            Title = h.Title,
            Items = h.Items.Select(m => new MediaCardItem
            {
                Metadata = m,
                Poster = ctx is null
                    ? null
                    : PosterImageLoader.GetThumb(ctx, m.Thumb ?? m.ParentThumb ?? m.GrandparentThumb)
            }).ToList()
        }).ToList();
    }

    public void ReapplyPreferences()
    {
        if (_rawHubs.Count == 0) return;
        ApplyHomeFilter();
    }
}
