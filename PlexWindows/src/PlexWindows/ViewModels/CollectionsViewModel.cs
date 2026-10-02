using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Server;

namespace PlexWindows.ViewModels;

public partial class CollectionsViewModel : ObservableObject
{
    private readonly PlexApiClient _api;
    private readonly ConnectionManager _connections;

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private string _title = "Collections";
    [ObservableProperty] private IReadOnlyList<MediaCardItem> _collections = Array.Empty<MediaCardItem>();
    [ObservableProperty] private IReadOnlyList<MediaCardItem> _children = Array.Empty<MediaCardItem>();
    [ObservableProperty] private bool _showingChildren;

    private PlexMetadata? _selectedCollection;

    public CollectionsViewModel(PlexApiClient api, ConnectionManager connections)
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
        ShowingChildren = false;
        Title = "Collections";
        try
        {
            var list = (await _api.FetchCollectionsAsync(ctx.BaseUrl, ctx.Token)).ToList();
            if (list.Count == 0)
            {
                // Per-section fallback (matches iOS CollectionsRepository)
                var sections = await _api.FetchLibrarySectionsAsync(ctx.BaseUrl, ctx.Token);
                var seen = new HashSet<string>();
                foreach (var section in sections)
                {
                    var part = await _api.FetchSectionCollectionsAsync(section.Key, ctx.BaseUrl, ctx.Token);
                    foreach (var item in part)
                    {
                        if (seen.Add(item.RatingKey))
                            list.Add(item);
                    }
                }
            }

            Collections = list.Select(m => ToCard(m, ctx)).ToList();
            if (Collections.Count == 0)
                StatusMessage = "No collections found.";
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
    public async Task OpenCollectionAsync(MediaCardItem card)
    {
        var ctx = CurrentContext;
        if (ctx is null) return;
        _selectedCollection = card.Metadata;
        Title = card.Title;
        IsLoading = true;
        try
        {
            var items = await _api.FetchCollectionChildrenAsync(card.RatingKey, ctx.BaseUrl, ctx.Token);
            Children = items.Select(m => ToCard(m, ctx)).ToList();
            ShowingChildren = true;
            if (Children.Count == 0)
                StatusMessage = "Collection is empty.";
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
        ShowingChildren = false;
        Title = "Collections";
        Children = Array.Empty<MediaCardItem>();
        StatusMessage = "";
    }

    private static MediaCardItem ToCard(PlexMetadata m, ServerContext ctx) => new()
    {
        Metadata = m,
        Poster = PosterImageLoader.GetThumb(ctx, m.Thumb)
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
