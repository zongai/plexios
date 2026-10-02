using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Server;

namespace PlexWindows.ViewModels;

public partial class PlaylistsViewModel : ObservableObject
{
    private readonly PlexApiClient _api;
    private readonly ConnectionManager _connections;

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private string _title = "Playlists";
    [ObservableProperty] private IReadOnlyList<MediaCardItem> _playlists = Array.Empty<MediaCardItem>();
    [ObservableProperty] private IReadOnlyList<MediaCardItem> _items = Array.Empty<MediaCardItem>();
    [ObservableProperty] private bool _showingItems;

    public PlaylistsViewModel(PlexApiClient api, ConnectionManager connections)
    {
        _api = api;
        _connections = connections;
    }

    public async Task LoadAsync()
    {
        var ctx = CurrentContext;
        if (ctx is null)
        {
            StatusMessage = "No active server.";
            return;
        }

        IsLoading = true;
        StatusMessage = "";
        ShowingItems = false;
        Title = "Playlists";
        try
        {
            var list = await _api.FetchPlaylistsAsync(ctx.BaseUrl, ctx.Token);
            Playlists = list.Select(m => ToCard(m, ctx)).ToList();
            if (Playlists.Count == 0)
                StatusMessage = "No playlists found.";
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    [RelayCommand]
    public async Task OpenPlaylistAsync(MediaCardItem card)
    {
        var ctx = CurrentContext;
        if (ctx is null) return;
        Title = card.Title;
        IsLoading = true;
        try
        {
            var list = await _api.FetchPlaylistItemsAsync(card.RatingKey, ctx.BaseUrl, ctx.Token);
            Items = list.Select(m => ToCard(m, ctx)).ToList();
            ShowingItems = true;
            if (Items.Count == 0)
                StatusMessage = "Playlist is empty.";
            else
                StatusMessage = "";
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
        }
        finally
        {
            IsLoading = false;
        }
    }

    [RelayCommand]
    public void BackToList()
    {
        ShowingItems = false;
        Title = "Playlists";
        Items = Array.Empty<MediaCardItem>();
        StatusMessage = "";
    }

    private static MediaCardItem ToCard(PlexMetadata m, ServerContext ctx) => new()
    {
        Metadata = m,
        Poster = PosterImageLoader.GetThumb(ctx, m.Thumb ?? m.ParentThumb ?? m.GrandparentThumb)
    };

    private ServerContext? CurrentContext
    {
        get
        {
            if (_connections.ActiveBaseUrl is null || string.IsNullOrEmpty(_connections.ActiveToken) ||
                _connections.ActiveServer is null)
                return null;
            return new ServerContext(
                _connections.ActiveBaseUrl,
                _connections.ActiveToken,
                _connections.ActiveServer.MachineIdentifier);
        }
    }
}
