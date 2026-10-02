using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Server;

namespace PlexWindows.ViewModels;

public partial class LibrariesViewModel : ObservableObject
{
    private readonly PlexApiClient _api;
    private readonly ConnectionManager _connections;

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private IReadOnlyList<PlexLibrary> _libraries = Array.Empty<PlexLibrary>();
    [ObservableProperty] private PlexLibrary? _selectedLibrary;
    [ObservableProperty] private IReadOnlyList<MediaCardItem> _items = Array.Empty<MediaCardItem>();
    [ObservableProperty] private string _title = "Libraries";

    public PlexLibraryType? FilterType { get; set; }

    public LibrariesViewModel(PlexApiClient api, ConnectionManager connections)
    {
        _api = api;
        _connections = connections;
    }

    public async Task LoadLibrariesAsync()
    {
        if (_connections.ActiveBaseUrl is null || string.IsNullOrEmpty(_connections.ActiveToken))
        {
            StatusMessage = "No active server.";
            return;
        }

        IsLoading = true;
        StatusMessage = "";
        try
        {
            var all = await _api.FetchLibrarySectionsAsync(_connections.ActiveBaseUrl, _connections.ActiveToken);
            Libraries = FilterType is { } t
                ? all.Where(l => l.Type == t).ToList()
                : all.ToList();
            if (Libraries.Count == 1)
                await SelectLibraryAsync(Libraries[0]);
            else if (Libraries.Count == 0)
                StatusMessage = "No libraries found.";
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
    public async Task SelectLibraryAsync(PlexLibrary library)
    {
        SelectedLibrary = library;
        Title = library.Title;
        await LoadItemsAsync();
    }

    public async Task LoadItemsAsync(int start = 0, int size = 100)
    {
        if (SelectedLibrary is null || CurrentContext is null) return;

        IsLoading = true;
        try
        {
            var ctx = CurrentContext;
            var page = await _api.FetchLibraryAllAsync(
                SelectedLibrary.Key, ctx.BaseUrl, ctx.Token, start, size);
            Items = page.Select(m => new MediaCardItem
            {
                Metadata = m,
                Poster = PosterImageLoader.GetThumb(ctx, m.Thumb)
            }).ToList();
            StatusMessage = Items.Count == 0 ? "Library is empty." : "";
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

    public ServerContext? CurrentContext
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
