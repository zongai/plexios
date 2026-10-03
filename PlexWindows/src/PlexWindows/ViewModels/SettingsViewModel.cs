using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Models;
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

    [ObservableProperty] private bool _autoPlayNextEpisode;
    [ObservableProperty] private bool _subtitlesEnabled = true;
    [ObservableProperty] private string _preferredAudioLanguage = "";
    [ObservableProperty] private string _preferredSubtitleLanguage = "";
    [ObservableProperty] private double _maxRemoteBitrateMbps = 20;
    [ObservableProperty] private string _playerBackend = "auto";
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private string _accountStatus = "Signed in";
    [ObservableProperty] private string _activeServerSummary = "";

    public ObservableCollection<PlexServer> Servers { get; } = new();

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
        ConnectionManager connections)
    {
        _settings = settings;
        _auth = auth;
        _connections = connections;
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

    public string AppVersion =>
        typeof(SettingsViewModel).Assembly.GetName().Version?.ToString() ?? "1.0";

    public record QualityOption(double Mbps, string Label)
    {
        public override string ToString() => Label;
    }
}
