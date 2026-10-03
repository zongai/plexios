using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Server;

namespace PlexWindows.ViewModels;

public partial class FavoritesViewModel : ObservableObject
{
    private readonly PlexApiClient _api;
    private readonly ConnectionManager _connections;

    [ObservableProperty] private ObservableCollection<MediaCardItem> _items = new();
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private bool _isLoading;

    public FavoritesViewModel(PlexApiClient api, ConnectionManager connections)
    {
        _api = api;
        _connections = connections;
    }

    [RelayCommand]
    public async Task LoadAsync()
    {
        if (_connections.ActiveBaseUrl is null || string.IsNullOrEmpty(_connections.ActiveToken))
        {
            StatusMessage = "No active server";
            return;
        }

        IsLoading = true;
        StatusMessage = "";
        try
        {
            var list = await _api.FetchFavoritesAsync(
                _connections.ActiveBaseUrl, _connections.ActiveToken);
            var ctx = new ServerContext(
                _connections.ActiveBaseUrl,
                _connections.ActiveToken!,
                _connections.ActiveServer?.MachineIdentifier ?? "");
            Items = new ObservableCollection<MediaCardItem>(
                list.Select(m => new MediaCardItem
                {
                    Metadata = m,
                    Poster = PosterImageLoader.GetThumb(ctx, m.Thumb ?? m.ParentThumb ?? m.GrandparentThumb, width: 420, height: 630)
                }));
            StatusMessage = list.Count == 0 ? "No favorites yet" : "";
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
}
