using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using Microsoft.UI.Xaml.Media.Imaging;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Server;
using PlexWindows.Playback;

namespace PlexWindows.ViewModels;

public partial class DetailViewModel : ObservableObject
{
    private readonly PlexApiClient _api;
    private readonly ConnectionManager _connections;
    private readonly PlaybackDecisionEngine _decisionEngine;
    private readonly PlaybackUrlBuilder _urlBuilder;

    [ObservableProperty] private bool _isLoading;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private PlexMetadata? _item;
    [ObservableProperty] private IReadOnlyList<PlexMetadata> _children = Array.Empty<PlexMetadata>();
    [ObservableProperty] private IReadOnlyList<PlexHub> _related = Array.Empty<PlexHub>();
    [ObservableProperty] private string? _posterUrl;
    [ObservableProperty] private string? _backdropUrl;
    [ObservableProperty] private BitmapImage? _posterImage;

    public string? RatingKey { get; set; }

    public DetailViewModel(
        PlexApiClient api,
        ConnectionManager connections,
        PlaybackDecisionEngine decisionEngine,
        PlaybackUrlBuilder urlBuilder)
    {
        _api = api;
        _connections = connections;
        _decisionEngine = decisionEngine;
        _urlBuilder = urlBuilder;
    }

    public async Task LoadAsync()
    {
        if (string.IsNullOrEmpty(RatingKey) ||
            _connections.ActiveBaseUrl is null ||
            string.IsNullOrEmpty(_connections.ActiveToken))
        {
            StatusMessage = "Missing item or server.";
            return;
        }

        IsLoading = true;
        StatusMessage = "";
        try
        {
            Item = await _api.FetchMetadataAsync(RatingKey, _connections.ActiveBaseUrl, _connections.ActiveToken);
            var ctx = CurrentContext;
            if (ctx is not null)
            {
                PosterUrl = PlexImage.Thumb(ctx, Item.Thumb)?.ToString();
                BackdropUrl = PlexImage.Art(ctx, Item.Art ?? Item.Thumb)?.ToString();
                PosterImage = PosterImageLoader.GetThumb(ctx, Item.Thumb, width: 400, height: 600);
            }

            if (Item.Type is PlexMetadataType.Show or PlexMetadataType.Season or PlexMetadataType.Artist or PlexMetadataType.Album)
            {
                Children = await _api.FetchChildrenAsync(RatingKey, _connections.ActiveBaseUrl, _connections.ActiveToken);
            }

            try
            {
                Related = await _api.FetchRelatedAsync(RatingKey, _connections.ActiveBaseUrl, _connections.ActiveToken);
            }
            catch
            {
                Related = Array.Empty<PlexHub>();
            }
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

    /// <summary>
    /// Builds a PlaybackRequest for the current item (or a child episode).
    /// Fetches full metadata when Media parts are missing (hub/list items often omit them).
    /// </summary>
    public async Task<PlaybackRequest?> BuildPlaybackRequestAsync(PlexMetadata? target = null)
    {
        var meta = target ?? Item;
        var ctx = CurrentContext;
        if (meta is null || ctx is null) return null;

        // Hub cards rarely include Media/Part — pull full metadata before deciding
        if (meta.Media is null || meta.Media.Count == 0)
        {
            try
            {
                meta = await _api.FetchMetadataAsync(meta.RatingKey, ctx.BaseUrl, ctx.Token);
            }
            catch (Exception ex)
            {
                StatusMessage = "Failed to load media: " + ex.Message;
                return null;
            }
        }

        if (meta.Media is null || meta.Media.Count == 0)
        {
            StatusMessage = "No playable media on this item.";
            return null;
        }

        var network = _connections.ActiveNetworkClass;
        var decision = _decisionEngine.Decide(meta, network);
        var url = _urlBuilder.Build(ctx, meta, decision);
        var start = meta.ViewOffset ?? 0;
        if (meta.Duration is long d && start > d * 0.95)
            start = 0;

        return new PlaybackRequest
        {
            Metadata = meta,
            Context = ctx,
            Network = network,
            Decision = decision,
            MediaUrl = url,
            StartPositionMs = start
        };
    }

    /// <summary>Sync wrapper for call sites that cannot await (prefer async).</summary>
    public PlaybackRequest? BuildPlaybackRequest(PlexMetadata? target = null)
        => BuildPlaybackRequestAsync(target).GetAwaiter().GetResult();

    [RelayCommand]
    public async Task ToggleFavoriteAsync()
    {
        if (Item is null || CurrentContext is null) return;
        var next = !Item.IsFavorite;
        try
        {
            await _api.RateAsync(Item.Key, next ? 10 : 0, CurrentContext.BaseUrl, CurrentContext.Token);
            await LoadAsync();
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
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
