using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Plex.Auth;
using PlexWindows.Plex.Server;
using PlexWindows.Services;

namespace PlexWindows.ViewModels;

/// <summary>
/// Settings VM aligned with iOS SettingsTabView sections:
/// Account &amp; Server · Playback · Player engine · Storage · About.
/// </summary>
public partial class SettingsViewModel : ObservableObject
{
    private readonly AppSettings _settings;
    private readonly AuthenticationService _auth;
    private readonly ConnectionManager _connections;
    private readonly PlexApiClient _api;

    [ObservableProperty] private bool _autoPlayNextEpisode;
    [ObservableProperty] private bool _subtitlesEnabled = true;
    [ObservableProperty] private string _preferredAudioLanguage = "";
    [ObservableProperty] private string _preferredSubtitleLanguage = "";
    [ObservableProperty] private double _maxRemoteBitrateMbps = 20;
    [ObservableProperty] private string _playerBackend = "auto";
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private string _accountStatus = "Signed in";
    [ObservableProperty] private string _activeServerSummary = "";
    [ObservableProperty] private bool _showContinueWatching = true;
    [ObservableProperty] private bool _showRecentlyPlayed = true;
    [ObservableProperty] private int _maxItemsPerHub = 20;
    public ObservableCollection<LibraryToggleItem> Libraries { get; } = new();

    public ObservableCollection<PlexServer> Servers { get; } = new();

    public IReadOnlyList<int> MaxItemsOptions { get; } = [10, 15, 20, 30, 50];

    public IReadOnlyList<string> BackendOptions { get; } =
        ["auto", "mediaFoundation", "libVlc"];

    /// <summary>Matches iOS max quality presets (Mbps display; 0 = Original).</summary>
    public IReadOnlyList<QualityOption> QualityOptions { get; } =
    [
        new(0, "Original"),
        new(20, "20 Mbps"),
        new(12, "12 Mbps"),
        new(8, "8 Mbps"),
        new(4, "4 Mbps"),
        new(2, "2 Mbps")
    ];

    [ObservableProperty] private QualityOption? _selectedQuality;

    public SettingsViewModel(
        AppSettings settings,
        AuthenticationService auth,
        ConnectionManager connections,
        PlexApiClient api)
    {
        _settings = settings;
        _auth = auth;
        _connections = connections;
        _api = api;
        Load();
    }

    public void Load()
    {
        AutoPlayNextEpisode = _settings.AutoPlayNextEpisode;
        SubtitlesEnabled = _settings.SubtitlesEnabled;
        PreferredAudioLanguage = _settings.PreferredAudioLanguage ?? "";
        PreferredSubtitleLanguage = _settings.PreferredSubtitleLanguage ?? "";
        MaxRemoteBitrateMbps = Math.Max(0, _settings.MaxRemoteBitrate / 1_000_000.0);
        PlayerBackend = _settings.PlayerBackend;
        SelectedQuality = QualityOptions.FirstOrDefault(q =>
            Math.Abs(q.Mbps - MaxRemoteBitrateMbps) < 0.5)
            ?? QualityOptions[0];

        ShowContinueWatching = _settings.ShowContinueWatching;
        ShowRecentlyPlayed = _settings.ShowRecentlyPlayed;
        MaxItemsPerHub = _settings.MaxItemsPerHub;
        _ = LoadLibrariesAsync();

        AccountStatus = _auth.State is AuthState.SignedIn ? "Signed in" : "Signed out";
        ActiveServerSummary = _connections.ActiveServer is { } s
            ? $"{s.Name}" + (s.PreferredConnection is { } c ? $" · {c.Uri}" : "")
            : "No server selected";

        Servers.Clear();
        foreach (var server in _connections.Servers)
            Servers.Add(server);

        StatusMessage = "";
    }

    partial void OnSelectedQualityChanged(QualityOption? value)
    {
        if (value is null) return;
        MaxRemoteBitrateMbps = value.Mbps == 0 ? 20 : value.Mbps;
    }

    [RelayCommand]
    public void Save()
    {
        _settings.AutoPlayNextEpisode = AutoPlayNextEpisode;
        _settings.SubtitlesEnabled = SubtitlesEnabled;
        _settings.PreferredAudioLanguage = string.IsNullOrWhiteSpace(PreferredAudioLanguage)
            ? null : PreferredAudioLanguage.Trim();
        _settings.PreferredSubtitleLanguage = string.IsNullOrWhiteSpace(PreferredSubtitleLanguage)
            ? null : PreferredSubtitleLanguage.Trim();
        // 0 / Original → keep a high remote cap; else selected Mbps
        var mbps = SelectedQuality?.Mbps ?? MaxRemoteBitrateMbps;
        _settings.MaxRemoteBitrate = mbps <= 0
            ? 100_000_000
            : (int)Math.Round(Math.Clamp(mbps, 1, 100) * 1_000_000);
        _settings.PlayerBackend = PlayerBackend;
        _settings.ShowContinueWatching = ShowContinueWatching;
        _settings.ShowRecentlyPlayed = ShowRecentlyPlayed;
        _settings.MaxItemsPerHub = MaxItemsPerHub;
        var disabled = new HashSet<string>(StringComparer.Ordinal);
        foreach (var lib in Libraries)
        {
            if (!lib.IsEnabled) disabled.Add(lib.Key);
        }
        _settings.DisabledLibraryKeys = disabled;
        StatusMessage = "Saved.";
    }

    [RelayCommand]
    public async Task RefreshServersAsync()
    {
        var token = _auth.AuthToken;
        if (string.IsNullOrEmpty(token))
        {
            StatusMessage = "Not signed in.";
            return;
        }
        StatusMessage = "Refreshing servers…";
        await _connections.DiscoverAsync(token);
        Load();
        StatusMessage = "Servers refreshed.";
    }

    [RelayCommand]
    public void SelectServer(PlexServer? server)
    {
        if (server is null) return;
        _connections.SelectServer(server);
        Load();
        StatusMessage = $"Server: {server.Name}";
    }

    [RelayCommand]
    public void ClearImageCache()
    {
        PosterImageLoader.Clear();
        StatusMessage = "Image cache cleared.";
    }

    [RelayCommand]
    public void SignOut()
    {
        _auth.SignOut();
        AccountStatus = "Signed out";
        StatusMessage = "Signed out.";
    }

    private async Task LoadLibrariesAsync()
    {
        Libraries.Clear();
        try
        {
            if (_connections.ActiveBaseUrl is null || string.IsNullOrEmpty(_connections.ActiveToken))
                return;
            var libs = await _api.FetchLibrarySectionsAsync(_connections.ActiveBaseUrl, _connections.ActiveToken);
            var disabled = _settings.DisabledLibraryKeys;
            foreach (var lib in libs)
            {
                Libraries.Add(new LibraryToggleItem
                {
                    Key = lib.Key,
                    Title = lib.Title,
                    IsEnabled = !disabled.Contains(lib.Key)
                });
            }
        }
        catch { /* ignore */ }
    }

    public string AppVersion =>
        typeof(SettingsViewModel).Assembly.GetName().Version?.ToString() ?? "1.0";

    public record QualityOption(double Mbps, string Label)
    {
        public override string ToString() => Label;
    }
}

public partial class LibraryToggleItem : ObservableObject
{
    public string Key { get; set; } = "";
    public string Title { get; set; } = "";
    [ObservableProperty] private bool _isEnabled = true;
}
