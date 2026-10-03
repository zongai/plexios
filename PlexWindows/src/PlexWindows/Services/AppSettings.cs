using System.Text.Json;

namespace PlexWindows.Services;

/// <summary>
/// Unified settings contract for Windows.
/// File-backed (LocalApplicationData) so it works for both packaged and
/// unpackaged self-contained builds — ApplicationData.Current is unavailable unpackaged.
/// Token is never stored here — see AuthenticationService / DPAPI.
/// </summary>
public sealed class AppSettings
{
    private static readonly string StorePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "PlexWindows",
        "settings.json");

    private static readonly JsonSerializerOptions JsonOpts = new()
    {
        WriteIndented = true,
        PropertyNameCaseInsensitive = true
    };

    private readonly object _gate = new();
    private SettingsData _data;

    public AppSettings()
    {
        _data = Load();
    }

    public bool AutoPlayNextEpisode
    {
        get => _data.AutoPlayNextEpisode;
        set { _data.AutoPlayNextEpisode = value; Save(); }
    }

    /// <summary>Prefer enabling subtitles when tracks are available (iOS parity).</summary>
    public bool SubtitlesEnabled
    {
        get => _data.SubtitlesEnabled;
        set { _data.SubtitlesEnabled = value; Save(); }
    }

    public string? PreferredAudioLanguage
    {
        get => _data.PreferredAudioLanguage;
        set { _data.PreferredAudioLanguage = value; Save(); }
    }

    public string? PreferredSubtitleLanguage
    {
        get => _data.PreferredSubtitleLanguage;
        set { _data.PreferredSubtitleLanguage = value; Save(); }
    }

    public int MaxRemoteBitrate
    {
        get => _data.MaxRemoteBitrate;
        set { _data.MaxRemoteBitrate = value; Save(); }
    }

    /// <summary>auto | mediaFoundation | libVlc</summary>
    public string PlayerBackend
    {
        get => string.IsNullOrWhiteSpace(_data.PlayerBackend) ? "auto" : _data.PlayerBackend!;
        set { _data.PlayerBackend = value; Save(); }
    }

    private static SettingsData Load()
    {
        try
        {
            if (File.Exists(StorePath))
            {
                var json = File.ReadAllText(StorePath);
                var data = JsonSerializer.Deserialize<SettingsData>(json, JsonOpts);
                if (data is not null) return data;
            }
        }
        catch
        {
            // corrupt file — fall through to defaults
        }
        return SettingsData.CreateDefault();
    }

    private void Save()
    {
        lock (_gate)
        {
            try
            {
                var dir = Path.GetDirectoryName(StorePath)!;
                Directory.CreateDirectory(dir);
                var json = JsonSerializer.Serialize(_data, JsonOpts);
                File.WriteAllText(StorePath, json);
            }
            catch
            {
                // best-effort
            }
        }
    }

    private sealed class SettingsData
    {
        public bool AutoPlayNextEpisode { get; set; } = true;
        public bool SubtitlesEnabled { get; set; } = true;
        public string? PreferredAudioLanguage { get; set; }
        public string? PreferredSubtitleLanguage { get; set; }
        public int MaxRemoteBitrate { get; set; } = 20_000_000;
        public string? PlayerBackend { get; set; } = "auto";

        public static SettingsData CreateDefault() => new();
    }
}
