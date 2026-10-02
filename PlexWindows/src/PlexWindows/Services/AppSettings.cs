using Windows.Storage;

namespace PlexWindows.Services;

/// <summary>
/// Unified settings contract (docs/settings-contract.md) for Windows.
/// Token is never stored here — see AuthenticationService / DPAPI.
/// </summary>
public sealed class AppSettings
{
    private readonly ApplicationDataContainer _local =
        ApplicationData.Current.LocalSettings;

    public bool AutoPlayNextEpisode
    {
        get => GetBool(nameof(AutoPlayNextEpisode), true);
        set => Set(nameof(AutoPlayNextEpisode), value);
    }

    public string? PreferredAudioLanguage
    {
        get => _local.Values[nameof(PreferredAudioLanguage)] as string;
        set => Set(nameof(PreferredAudioLanguage), value);
    }

    public string? PreferredSubtitleLanguage
    {
        get => _local.Values[nameof(PreferredSubtitleLanguage)] as string;
        set => Set(nameof(PreferredSubtitleLanguage), value);
    }

    public int MaxRemoteBitrate
    {
        get => GetInt(nameof(MaxRemoteBitrate), 20_000_000);
        set => Set(nameof(MaxRemoteBitrate), value);
    }

    /// <summary>auto | mediaFoundation | libVlc</summary>
    public string PlayerBackend
    {
        get => _local.Values[nameof(PlayerBackend)] as string ?? "auto";
        set => Set(nameof(PlayerBackend), value);
    }

    private bool GetBool(string key, bool fallback) =>
        _local.Values[key] is bool b ? b : fallback;

    private int GetInt(string key, int fallback) =>
        _local.Values[key] is int i ? i : fallback;

    private void Set(string key, object? value)
    {
        if (value is null) _local.Values.Remove(key);
        else _local.Values[key] = value;
    }
}
