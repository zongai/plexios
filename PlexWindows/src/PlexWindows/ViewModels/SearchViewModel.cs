using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Server;

namespace PlexWindows.ViewModels;

public sealed class SearchHubCards
{
    public required string Title { get; init; }
    public required IReadOnlyList<MediaCardItem> Items { get; init; }
}

public partial class SearchViewModel : ObservableObject
{
    private readonly PlexApiClient _api;
    private readonly ConnectionManager _connections;
    private CancellationTokenSource? _cts;

    [ObservableProperty] private string _query = "";
    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private IReadOnlyList<SearchHubCards> _results = Array.Empty<SearchHubCards>();

    public SearchViewModel(PlexApiClient api, ConnectionManager connections)
    {
        _api = api;
        _connections = connections;
    }

    [RelayCommand]
    public async Task SearchAsync()
    {
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var ct = _cts.Token;
        var q = Query.Trim();
        if (q.Length == 0)
        {
            Results = Array.Empty<SearchHubCards>();
            StatusMessage = "";
            return;
        }

        if (_connections.ActiveBaseUrl is null || string.IsNullOrEmpty(_connections.ActiveToken) ||
            _connections.ActiveServer is null)
        {
            StatusMessage = "No active server.";
            return;
        }

        IsLoading = true;
        StatusMessage = "";
        try
        {
            await Task.Delay(250, ct);
            var ctx = new ServerContext(
                _connections.ActiveBaseUrl,
                _connections.ActiveToken,
                _connections.ActiveServer.MachineIdentifier);

            var hubs = await _api.SearchAsync(q, ctx.BaseUrl, ctx.Token, ct);
            Results = hubs.Select(h => new SearchHubCards
            {
                Title = h.Title,
                Items = h.Items.Select(m => new MediaCardItem
                {
                    Metadata = m,
                    Poster = PosterImageLoader.GetThumb(ctx, m.Thumb ?? m.ParentThumb ?? m.GrandparentThumb)
                }).ToList()
            }).ToList();

            if (Results.Count == 0 || Results.All(h => h.Items.Count == 0))
                StatusMessage = "No results.";
        }
        catch (OperationCanceledException) { /* ignore */ }
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
