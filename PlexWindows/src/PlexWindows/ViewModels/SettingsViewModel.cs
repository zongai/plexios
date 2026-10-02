using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Helpers;
using PlexWindows.Plex.Auth;
using PlexWindows.Services;

namespace PlexWindows.ViewModels;

public partial class SettingsViewModel : ObservableObject
{
    private readonly AppSettings _settings;
    private readonly AuthenticationService _auth;

    [ObservableProperty] private bool _autoPlayNextEpisode;
    [ObservableProperty] private string _preferredAudioLanguage = "";
    [ObservableProperty] private string _preferredSubtitleLanguage = "";
    [ObservableProperty] private int _maxRemoteBitrateMbps = 20;
    [ObservableProperty] private string _playerBackend = "auto";
    [ObservableProperty] private string _statusMessage = "";

    public IReadOnlyList<string> BackendOptions { get; } = ["auto", "mediaFoundation", "libVlc"];

    public SettingsViewModel(AppSettings settings, AuthenticationService auth)
    {
        _settings = settings;
        _auth = auth;
        Load();
    }

    public void Load()
    {
        AutoPlayNextEpisode = _settings.AutoPlayNextEpisode;
        PreferredAudioLanguage = _settings.PreferredAudioLanguage ?? "";
        PreferredSubtitleLanguage = _settings.PreferredSubtitleLanguage ?? "";
        MaxRemoteBitrateMbps = Math.Max(1, _settings.MaxRemoteBitrate / 1_000_000);
        PlayerBackend = _settings.PlayerBackend;
    }

    [RelayCommand]
    public void Save()
    {
        _settings.AutoPlayNextEpisode = AutoPlayNextEpisode;
        _settings.PreferredAudioLanguage = string.IsNullOrWhiteSpace(PreferredAudioLanguage)
            ? null : PreferredAudioLanguage.Trim();
        _settings.PreferredSubtitleLanguage = string.IsNullOrWhiteSpace(PreferredSubtitleLanguage)
            ? null : PreferredSubtitleLanguage.Trim();
        _settings.MaxRemoteBitrate = MaxRemoteBitrateMbps * 1_000_000;
        _settings.PlayerBackend = PlayerBackend;
        StatusMessage = "Saved.";
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
        StatusMessage = "Signed out.";
    }
}
