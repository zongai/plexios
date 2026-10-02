using CommunityToolkit.Mvvm.ComponentModel;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Auth;
using PlexWindows.Plex.Server;

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

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private IReadOnlyList<HubCards> _hubs = Array.Empty<HubCards>();

    public HomeViewModel(PlexApiClient api, AuthenticationService auth, ConnectionManager connections)
    {
        _api = api;
        _auth = auth;
        _connections = connections;
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
            Hubs = hubs.Select(h => new HubCards
            {
                Title = h.Title,
                Items = h.Items.Select(m => new MediaCardItem
                {
                    Metadata = m,
                    Poster = PosterImageLoader.GetThumb(ctx, m.Thumb ?? m.ParentThumb ?? m.GrandparentThumb)
                }).ToList()
            }).ToList();
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
}
