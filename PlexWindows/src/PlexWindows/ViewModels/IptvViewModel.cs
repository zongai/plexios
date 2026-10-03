using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Iptv;
using PlexWindows.Models;
using PlexWindows.Playback;

namespace PlexWindows.ViewModels;

public partial class IptvViewModel : ObservableObject
{
    private readonly IptvRepository _repo;

    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private string _newName = "";
    [ObservableProperty] private string _newUrl = "";
    [ObservableProperty] private string _searchText = "";
    [ObservableProperty] private string? _selectedGroup;

    public ObservableCollection<IptvPlaylist> Playlists { get; } = new();
    public ObservableCollection<IptvChannel> Channels { get; } = new();
    public ObservableCollection<string> Groups { get; } = new();

    private List<IptvChannel> _allChannels = [];

    public IptvViewModel(IptvRepository repo)
    {
        _repo = repo;
        Reload();
    }

    public void Reload()
    {
        Playlists.Clear();
        foreach (var p in _repo.LoadPlaylists())
            Playlists.Add(p);
        _allChannels = _repo.AllEnabledChannels();
        RebuildGroups();
        ApplyFilter();
        StatusMessage = _allChannels.Count == 0
            ? "Add an M3U playlist URL, then Refresh."
            : $"{_allChannels.Count} channels";
    }

    private void RebuildGroups()
    {
        Groups.Clear();
        Groups.Add("(All)");
        foreach (var g in _allChannels.Select(c => c.Group).Where(g => !string.IsNullOrWhiteSpace(g)).Distinct().OrderBy(x => x))
            Groups.Add(g!);
    }

    partial void OnSearchTextChanged(string value) => ApplyFilter();
    partial void OnSelectedGroupChanged(string? value) => ApplyFilter();

    public void ApplyFilter()
    {
        IEnumerable<IptvChannel> q = _allChannels;
        if (!string.IsNullOrWhiteSpace(SelectedGroup) && SelectedGroup != "(All)")
            q = q.Where(c => c.Group == SelectedGroup);
        var s = SearchText?.Trim() ?? "";
        if (s.Length > 0)
            q = q.Where(c =>
                c.Name.Contains(s, StringComparison.OrdinalIgnoreCase) ||
                (c.Group?.Contains(s, StringComparison.OrdinalIgnoreCase) ?? false) ||
                (c.TvgId?.Contains(s, StringComparison.OrdinalIgnoreCase) ?? false));
        Channels.Clear();
        foreach (var c in q.Take(500))
            Channels.Add(c);
    }

    [RelayCommand]
    public async Task AddAndRefreshAsync()
    {
        if (string.IsNullOrWhiteSpace(NewUrl))
        {
            StatusMessage = "Playlist URL required.";
            return;
        }
        IsBusy = true;
        StatusMessage = "Downloading playlist…";
        try
        {
            var pl = new IptvPlaylist
            {
                Name = string.IsNullOrWhiteSpace(NewName) ? "Playlist" : NewName.Trim(),
                Url = NewUrl.Trim()
            };
            _repo.AddPlaylist(pl);
            await _repo.RefreshPlaylistAsync(pl);
            NewName = "";
            NewUrl = "";
            Reload();
            StatusMessage = $"Loaded {pl.ChannelCount} channels.";
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    [RelayCommand]
    public async Task RefreshPlaylistAsync(IptvPlaylist? pl)
    {
        if (pl is null) return;
        IsBusy = true;
        StatusMessage = $"Refreshing {pl.Name}…";
        try
        {
            await _repo.RefreshPlaylistAsync(pl);
            Reload();
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
        }
        finally
        {
            IsBusy = false;
        }
    }

    [RelayCommand]
    public void DeletePlaylist(IptvPlaylist? pl)
    {
        if (pl is null) return;
        _repo.DeletePlaylist(pl.Id);
        Reload();
    }

    /// <summary>Build a synthetic PlaybackRequest for live IPTV stream.</summary>
    public static PlaybackRequest BuildStreamRequest(IptvChannel channel)
    {
        if (!Uri.TryCreate(channel.StreamUrl, UriKind.Absolute, out var url))
            throw new InvalidOperationException("Invalid stream URL");

        var meta = new PlexMetadata
        {
            RatingKey = "iptv-" + channel.Id,
            Key = "/iptv/" + channel.Id,
            Type = PlexMetadataType.Unknown,
            Title = channel.Name,
            Thumb = channel.LogoUrl,
            Media =
            [
                new PlexMedia
                {
                    Id = 1,
                    Parts =
                    [
                        new PlexPart { Id = 1, Key = channel.StreamUrl }
                    ]
                }
            ]
        };

        // Dummy context — not used for direct URL play
        var ctx = new ServerContext(new Uri("http://localhost/"), "", "iptv");
        var decision = new PlaybackDecision(
            PlaybackMode.DirectPlay,
            "IPTV direct stream",
            PlaybackBackend.System,
            0, 0, null, null, false, null);

        return new PlaybackRequest
        {
            Metadata = meta,
            Context = ctx,
            Network = NetworkClass.Local,
            Decision = decision,
            MediaUrl = url,
            StartPositionMs = 0
        };
    }
}
