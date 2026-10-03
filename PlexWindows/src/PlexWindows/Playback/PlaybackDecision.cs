using PlexWindows.Services;
namespace PlexWindows.Playback;

/// <summary>Contract: system (MF/AV/Exo) vs vlc fallback.</summary>
public enum PlaybackBackend
{
    System,
    Vlc
}

public enum PlaybackMode
{
    DirectPlay,
    DirectStream,
    Transcode
}

public enum NetworkClass
{
    Local,
    Remote,
    Relay,
    Unknown
}

public sealed record PlaybackDecision(
    PlaybackMode Mode,
    string Reason,
    PlaybackBackend Backend,
    int MediaIndex,
    int PartIndex,
    int? SelectedAudioStreamId,
    int? SelectedSubtitleStreamId,  // null = off
    bool BurnInSubtitles,
    int? MaxBitrateKbps)
{
    public bool IsDirectPlay => Mode == PlaybackMode.DirectPlay;
}

/// <summary>
/// Platform capability matrix. Windows implementation declares what
/// Media Foundation / LibVLC can handle; decision engine stays platform-agnostic.
/// </summary>
public sealed class ClientCapabilities
{
    public HashSet<string> SupportedContainers { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public HashSet<string> SupportedVideoCodecs { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public HashSet<string> SupportedAudioCodecs { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public HashSet<string> SupportedSubtitleFormats { get; init; } = new(StringComparer.OrdinalIgnoreCase);
    public HashSet<string> RequiresBurnInFor { get; init; } = new(StringComparer.OrdinalIgnoreCase);

    public int MaxVideoWidth { get; init; } = 3840;
    public int MaxVideoHeight { get; init; } = 2160;
    public bool SupportsHdr10 { get; init; }
    public bool SupportsDolbyVision { get; init; }
    public int MaxAudioChannels { get; init; } = 8;

    public bool SupportsDirectPlay { get; init; } = true;
    public bool SupportsDirectStream { get; init; } = true;
    public bool SupportsTranscode { get; init; } = true;
    public bool SupportsHls { get; init; } = true;

    public bool SupportsPiP { get; init; }          // typically false on desktop
    public bool SupportsAirPlay { get; init; }      // false
    public bool SupportsBackgroundPlayback { get; init; } = true;
    public bool SupportsRemoteCommandCenter { get; init; } = true;

    /// <summary>Media Foundation primary matrix (stricter containers).</summary>
    public static ClientCapabilities MediaFoundationDefault { get; } = new()
    {
        SupportedContainers = new(StringComparer.OrdinalIgnoreCase)
            { "mp4", "m4v", "mov", "mpegts", "mpeg", "avi", "wmv", "asf" },
        SupportedVideoCodecs = new(StringComparer.OrdinalIgnoreCase)
            { "h264", "avc", "hevc", "h265", "mpeg2video", "mpeg4", "vc1", "wmv3", "vp9" },
        SupportedAudioCodecs = new(StringComparer.OrdinalIgnoreCase)
            { "aac", "mp3", "ac3", "eac3", "wmav2", "pcm", "flac", "opus" },
        SupportedSubtitleFormats = new(StringComparer.OrdinalIgnoreCase)
            { "srt", "vtt", "ttml", "dfxp" },
        RequiresBurnInFor = new(StringComparer.OrdinalIgnoreCase)
            { "pgs", "vobsub", "dvd", "idx", "ass", "ssa" },
        SupportsHdr10 = true,
        SupportsDolbyVision = false,
        MaxAudioChannels = 8,
        SupportsPiP = false,
        SupportsAirPlay = false,
        SupportsBackgroundPlayback = true,
        SupportsRemoteCommandCenter = true
    };

    /// <summary>LibVLC fallback matrix (broad Direct Play).</summary>
    public static ClientCapabilities LibVlcDefault { get; } = new()
    {
        SupportedContainers = new(StringComparer.OrdinalIgnoreCase)
            { "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "asf", "mpegts", "mpeg", "m2ts", "ts", "flv", "ogg" },
        SupportedVideoCodecs = new(StringComparer.OrdinalIgnoreCase)
            { "h264", "avc", "hevc", "h265", "mpeg2video", "mpeg4", "vc1", "wmv3", "vp8", "vp9", "av1" },
        SupportedAudioCodecs = new(StringComparer.OrdinalIgnoreCase)
            { "aac", "mp3", "ac3", "eac3", "wmav2", "pcm", "flac", "opus", "dts", "truehd" },
        SupportedSubtitleFormats = new(StringComparer.OrdinalIgnoreCase)
            { "srt", "vtt", "ttml", "dfxp", "ass", "ssa" },
        RequiresBurnInFor = new(StringComparer.OrdinalIgnoreCase)
            { "pgs", "vobsub", "dvd", "idx" },
        SupportsHdr10 = true,
        SupportsDolbyVision = false,
        MaxAudioChannels = 16,
        SupportsPiP = false,
        SupportsAirPlay = false,
        SupportsBackgroundPlayback = true,
        SupportsRemoteCommandCenter = true
    };

    /// <summary>Union used when Decision does not yet pick a backend matrix (compat).</summary>
    public static ClientCapabilities WindowsDefault { get; } = new()
    {
        // Broad set: LibVLC path can Direct Play nearly anything; MF path still
        // fails over when container/codec truly unsupported by MF.
        SupportedContainers = new(StringComparer.OrdinalIgnoreCase)
            { "mp4", "m4v", "mov", "mkv", "webm", "avi", "wmv", "asf", "mpegts", "mpeg", "m2ts", "ts" },
        SupportedVideoCodecs = new(StringComparer.OrdinalIgnoreCase)
            { "h264", "avc", "hevc", "h265", "mpeg2video", "mpeg4", "vc1", "wmv3", "vp8", "vp9", "av1" },
        SupportedAudioCodecs = new(StringComparer.OrdinalIgnoreCase)
            { "aac", "mp3", "ac3", "eac3", "wmav2", "pcm", "flac", "opus" },
        SupportedSubtitleFormats = new(StringComparer.OrdinalIgnoreCase)
            { "srt", "vtt", "ttml", "dfxp", "ass", "ssa" },
        RequiresBurnInFor = new(StringComparer.OrdinalIgnoreCase)
            { "pgs", "vobsub", "dvd", "idx" },
        SupportsHdr10 = true,
        SupportsDolbyVision = false,
        MaxAudioChannels = 8,
        SupportsPiP = false,
        SupportsAirPlay = false,
        SupportsBackgroundPlayback = true,
        SupportsRemoteCommandCenter = true
    };
}

public sealed class PlaybackPreferences
{
    public int? MaxVideoBitrateKbps { get; set; }
    public bool PreferDirectPlay { get; set; } = true;
    public bool AutoPlayNextEpisode { get; set; } = true;
    public bool SubtitlesEnabled { get; set; } = true;
    /// <summary>Priority list of ISO language codes (empty = Auto).</summary>
    public IReadOnlyList<string> PreferredAudioLanguages { get; set; } = Array.Empty<string>();
    public IReadOnlyList<string> PreferredSubtitleLanguages { get; set; } = Array.Empty<string>();

    public static PlaybackPreferences Default { get; } = new();
}

/// <summary>
/// Platform-agnostic decision engine. Port of iOS PlaybackDecisionEngine semantics.
/// </summary>
public sealed class PlaybackDecisionEngine
{
    private readonly ClientCapabilities _caps;
    private PlaybackPreferences _prefs;
    private readonly AppSettings? _settings;

    public PlaybackDecisionEngine(
        AppSettings? settings = null,
        ClientCapabilities? caps = null,
        PlaybackPreferences? prefs = null)
    {
        _settings = settings;
        _caps = caps ?? ClientCapabilities.WindowsDefault;
        _prefs = prefs ?? PlaybackPreferences.Default;
    }

    private void RefreshPrefs()
    {
        if (_settings is null) return;
        _prefs = new PlaybackPreferences
        {
            AutoPlayNextEpisode = _settings.AutoPlayNextEpisode,
            SubtitlesEnabled = _settings.SubtitlesEnabled,
            MaxVideoBitrateKbps = _settings.MaxRemoteBitrate > 0
                ? Math.Max(1000, _settings.MaxRemoteBitrate / 1000)
                : null,
            PreferredAudioLanguages = _settings.PreferredAudioLanguages,
            PreferredSubtitleLanguages = _settings.PreferredSubtitleLanguages,
        };
    }

    public PlaybackDecision Decide(
        Models.PlexMetadata metadata,
        NetworkClass network,
        int mediaIndex = 0,
        int partIndex = 0,
        int? forcedAudioId = null,
        int? forcedSubtitleId = null)
    {
        RefreshPrefs();
        var netBitrate = BitrateForNetwork(network);

        if (metadata.Media is null || metadata.Media.Count == 0)
        {
            return Transcode("No media versions available", 0, 0, null, null, false, netBitrate);
        }

        var mi = Math.Clamp(mediaIndex, 0, metadata.Media.Count - 1);
        var media = metadata.Media[mi];
        if (media.Parts is null || media.Parts.Count == 0)
        {
            return Transcode("Media has no parts", mi, 0, null, null, false, netBitrate);
        }

        var pi = Math.Clamp(partIndex, 0, media.Parts.Count - 1);
        var part = media.Parts[pi];
        var streams = part.Streams;

        var video = streams.FirstOrDefault(s => s.Type == Models.PlexStream.StreamType.Video);
        var audioStreams = streams.Where(s => s.Type == Models.PlexStream.StreamType.Audio).ToList();
        var subtitleStreams = streams.Where(s => s.Type == Models.PlexStream.StreamType.Subtitle).ToList();

        var audioId = SelectAudio(audioStreams, forcedAudioId);
        var selectedAudio = audioStreams.FirstOrDefault(s => s.Id == audioId);
        var (subtitleId, burnIn) = SelectSubtitle(subtitleStreams, forcedSubtitleId);

        var container = (part.Container ?? media.Container)?.ToLowerInvariant();
        var videoCodec = (video?.Codec ?? media.VideoCodec)?.ToLowerInvariant();
        var audioCodec = (selectedAudio?.Codec ?? media.AudioCodec)?.ToLowerInvariant();

        // User bitrate cap
        if (_prefs.MaxVideoBitrateKbps is int maxBr && media.Bitrate is int sourceBr && sourceBr > maxBr)
        {
            return Transcode(
                $"Source bitrate {sourceBr} kbps exceeds preference {maxBr} kbps",
                mi, pi, audioId, subtitleId, burnIn, maxBr);
        }

        // Resolution cap
        if (media.Width is int w && media.Height is int h &&
            (w > _caps.MaxVideoWidth || h > _caps.MaxVideoHeight))
        {
            return Transcode(
                $"Resolution {w}x{h} exceeds client max {_caps.MaxVideoWidth}x{_caps.MaxVideoHeight}",
                mi, pi, audioId, subtitleId, burnIn, netBitrate);
        }

        var containerOk = container is null || _caps.SupportedContainers.Contains(container);
        var videoOk = videoCodec is null || _caps.SupportedVideoCodecs.Contains(videoCodec);
        var audioOk = audioCodec is null || _caps.SupportedAudioCodecs.Contains(audioCodec);

        // Subtitle handling
        if (subtitleId is int sid)
        {
            var sub = subtitleStreams.FirstOrDefault(s => s.Id == sid);
            var subFormat = (sub?.Codec ?? sub?.Format)?.ToLowerInvariant();
            if (subFormat is not null && _caps.RequiresBurnInFor.Contains(subFormat))
            {
                burnIn = true;
            }
            else if (subFormat is not null && !_caps.SupportedSubtitleFormats.Contains(subFormat))
            {
                burnIn = true;
            }
        }

        if (burnIn)
        {
            // Burn-in requires transcode
            return Transcode(
                "Subtitle requires burn-in",
                mi, pi, audioId, subtitleId, true, netBitrate);
        }

        if (containerOk && videoOk && audioOk && _caps.SupportsDirectPlay && _prefs.PreferDirectPlay)
        {
            return new PlaybackDecision(
                PlaybackMode.DirectPlay,
                $"Direct Play: container={container}, video={videoCodec}, audio={audioCodec}",
                PlaybackBackend.System,
                mi, pi, audioId, subtitleId, false, _prefs.MaxVideoBitrateKbps);
        }

        // Direct Stream: codecs OK, container may need remux
        if (videoOk && audioOk && _caps.SupportsDirectStream)
        {
            return new PlaybackDecision(
                PlaybackMode.DirectStream,
                $"Direct Stream: video={videoCodec}, audio={audioCodec}, container remap",
                PlaybackBackend.System,
                mi, pi, audioId, subtitleId, false, _prefs.MaxVideoBitrateKbps);
        }

        return Transcode(
            $"Transcode required: containerOk={containerOk}, videoOk={videoOk}, audioOk={audioOk}",
            mi, pi, audioId, subtitleId, burnIn, netBitrate);
    }

    private int? SelectAudio(List<Models.PlexStream> streams, int? forced)
    {
        // Honor explicit user choice even if stream list is incomplete in metadata snapshot
        if (forced is int id && id > 0)
        {
            if (streams.Count == 0 || streams.Any(s => s.Id == id))
                return id;
        }
        foreach (var pref in _prefs.PreferredAudioLanguages.Where(s => !string.IsNullOrWhiteSpace(s)))
        {
            var match = streams.FirstOrDefault(s => MatchesLanguage(s, pref));
            if (match is not null) return match.Id;
        }
        var def = streams.FirstOrDefault(s => s.IsDefault) ?? streams.FirstOrDefault(s => s.IsSelected)
                  ?? streams.FirstOrDefault();
        return def?.Id;
    }

    private (int? id, bool burnIn) SelectSubtitle(List<Models.PlexStream> streams, int? forced)
    {
        if (forced is int id)
        {
            if (id < 0) return (null, false); // explicit off
            if (id > 0)
            {
                var s = streams.FirstOrDefault(x => x.Id == id);
                // Honor user choice even if snapshot streams are incomplete
                return (id, s is not null && RequiresBurnIn(s));
            }
        }
        if (!_prefs.SubtitlesEnabled)
            return (null, false);

        foreach (var pref in _prefs.PreferredSubtitleLanguages.Where(s => !string.IsNullOrWhiteSpace(s)))
        {
            var match = streams.FirstOrDefault(s => MatchesLanguage(s, pref));
            if (match is not null) return (match.Id, RequiresBurnIn(match));
        }
        var selected = streams.FirstOrDefault(s => s.IsSelected) ?? streams.FirstOrDefault(s => s.IsDefault);
        if (selected is not null) return (selected.Id, RequiresBurnIn(selected));
        if (_prefs.PreferredSubtitleLanguages.Count == 0)
        {
            var forcedSub = streams.FirstOrDefault(s => s.IsForced);
            if (forcedSub is not null) return (forcedSub.Id, RequiresBurnIn(forcedSub));
        }
        return (null, false);
    }

    private static bool MatchesLanguage(Models.PlexStream stream, string pref)
    {
        var p = pref.Trim().ToLowerInvariant();
        if (p.Length == 0) return false;
        var code = (stream.LanguageCode ?? "").ToLowerInvariant();
        var lang = (stream.Language ?? "").ToLowerInvariant();
        if (code == p || code.StartsWith(p + "-") || p.StartsWith(code + "-")) return true;
        if (lang.StartsWith(p)) return true;
        // zh matches zh-CN / zh-TW
        if (p == "zh" && (code.StartsWith("zh") || lang.Contains("chinese") || lang.Contains("中文"))) return true;
        return false;
    }

    private bool RequiresBurnIn(Models.PlexStream s)
    {
        var fmt = (s.Codec ?? s.Format ?? "").ToLowerInvariant();
        return _caps.RequiresBurnInFor.Contains(fmt);
    }

    private int? BitrateForNetwork(NetworkClass network)
    {
        if (_prefs.MaxVideoBitrateKbps is int userCap) return userCap;
        return network switch
        {
            NetworkClass.Local => null, // uncapped
            NetworkClass.Remote => 20_000, // 20 Mbps
            NetworkClass.Relay => 4_000,
            _ => 20_000
        };
    }

    private PlaybackDecision Transcode(
        string reason, int mi, int pi, int? audioId, int? subId, bool burnIn, int? maxBr = null)
        => new(PlaybackMode.Transcode, reason, PlaybackBackend.System, mi, pi, audioId, subId, burnIn, maxBr);
}


