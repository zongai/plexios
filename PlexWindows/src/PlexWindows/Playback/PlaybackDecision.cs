namespace PlexWindows.Playback;

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

    /// <summary>Conservative Windows defaults (Media Foundation + common codecs).</summary>
    public static ClientCapabilities WindowsDefault { get; } = new()
    {
        SupportedContainers = new(StringComparer.OrdinalIgnoreCase)
            { "mp4", "m4v", "mov", "mpegts", "mpeg", "avi", "wmv", "asf" },
        SupportedVideoCodecs = new(StringComparer.OrdinalIgnoreCase)
            { "h264", "avc", "hevc", "h265", "mpeg2video", "mpeg4", "vc1", "wmv3", "vp9" },
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

    public static PlaybackPreferences Default { get; } = new();
}

/// <summary>
/// Platform-agnostic decision engine. Port of iOS PlaybackDecisionEngine semantics.
/// </summary>
public sealed class PlaybackDecisionEngine
{
    private readonly ClientCapabilities _caps;
    private readonly PlaybackPreferences _prefs;

    public PlaybackDecisionEngine(ClientCapabilities? caps = null, PlaybackPreferences? prefs = null)
    {
        _caps = caps ?? ClientCapabilities.WindowsDefault;
        _prefs = prefs ?? PlaybackPreferences.Default;
    }

    public PlaybackDecision Decide(
        Models.PlexMetadata metadata,
        NetworkClass network,
        int mediaIndex = 0,
        int partIndex = 0,
        int? forcedAudioId = null,
        int? forcedSubtitleId = null)
    {
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
                mi, pi, audioId, subtitleId, false, _prefs.MaxVideoBitrateKbps);
        }

        // Direct Stream: codecs OK, container may need remux
        if (videoOk && audioOk && _caps.SupportsDirectStream)
        {
            return new PlaybackDecision(
                PlaybackMode.DirectStream,
                $"Direct Stream: video={videoCodec}, audio={audioCodec}, container remap",
                mi, pi, audioId, subtitleId, false, _prefs.MaxVideoBitrateKbps);
        }

        return Transcode(
            $"Transcode required: containerOk={containerOk}, videoOk={videoOk}, audioOk={audioOk}",
            mi, pi, audioId, subtitleId, burnIn, netBitrate);
    }

    private static int? SelectAudio(List<Models.PlexStream> streams, int? forced)
    {
        if (forced is int id && streams.Any(s => s.Id == id)) return id;
        var def = streams.FirstOrDefault(s => s.IsDefault) ?? streams.FirstOrDefault();
        return def?.Id;
    }

    private static (int? id, bool burnIn) SelectSubtitle(List<Models.PlexStream> streams, int? forced)
    {
        if (forced is int id)
        {
            if (id < 0) return (null, false); // explicit off
            if (streams.Any(s => s.Id == id)) return (id, false);
        }
        var forcedSub = streams.FirstOrDefault(s => s.IsForced);
        if (forcedSub is not null) return (forcedSub.Id, false);
        var def = streams.FirstOrDefault(s => s.IsDefault);
        return (def?.Id, false);
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
        => new(PlaybackMode.Transcode, reason, mi, pi, audioId, subId, burnIn, maxBr);
}


