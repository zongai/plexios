namespace PlexWindows.Playback;

/// <summary>
/// Cross-platform playback error codes (docs/cross-platform-playback-contract.md §8).
/// Wire values align with iOS PlaybackErrorCode / Android PlaybackErrorCode.
/// </summary>
public enum PlaybackErrorCode
{
    Network,
    MediaUnavailable,
    Decode,
    Unsupported,
    Subtitle,
    Cancelled,
    Session,
    Backend,
    Track,
    Unknown
}

public enum PlaybackSuggestedAction
{
    Retry,
    SwitchBackend,
    Transcode,
    None
}

public sealed record PlaybackError(
    PlaybackErrorCode Code,
    string Message,
    bool Recoverable,
    PlaybackSuggestedAction SuggestedAction)
{
    public string WireCode => Code switch
    {
        PlaybackErrorCode.Network => "network",
        PlaybackErrorCode.MediaUnavailable => "mediaUnavailable",
        PlaybackErrorCode.Decode => "decode",
        PlaybackErrorCode.Unsupported => "unsupported",
        PlaybackErrorCode.Subtitle => "subtitle",
        PlaybackErrorCode.Cancelled => "cancelled",
        PlaybackErrorCode.Session => "session",
        PlaybackErrorCode.Backend => "backend",
        PlaybackErrorCode.Track => "track",
        _ => "unknown"
    };

    public static PlaybackError FromMessage(string message, PlaybackErrorCode? hint = null)
    {
        var msg = string.IsNullOrWhiteSpace(message) ? "Unknown playback error" : message;
        var code = hint ?? Classify(msg);
        var recoverable = code is not (PlaybackErrorCode.Cancelled or PlaybackErrorCode.Unsupported
            or PlaybackErrorCode.MediaUnavailable);
        var action = code switch
        {
            PlaybackErrorCode.Network or PlaybackErrorCode.Session => PlaybackSuggestedAction.Retry,
            PlaybackErrorCode.Decode or PlaybackErrorCode.Backend => PlaybackSuggestedAction.SwitchBackend,
            PlaybackErrorCode.Unsupported => PlaybackSuggestedAction.Transcode,
            PlaybackErrorCode.Subtitle or PlaybackErrorCode.Track => PlaybackSuggestedAction.Retry,
            _ => PlaybackSuggestedAction.None
        };
        return new PlaybackError(code, msg, recoverable, action);
    }

    private static PlaybackErrorCode Classify(string msg)
    {
        if (Contains(msg, "network") || Contains(msg, "connect") || Contains(msg, "timeout"))
            return PlaybackErrorCode.Network;
        if (Contains(msg, "404") || Contains(msg, "not available") || Contains(msg, "unavailable"))
            return PlaybackErrorCode.MediaUnavailable;
        if (Contains(msg, "subtitle") || Contains(msg, "spu"))
            return PlaybackErrorCode.Subtitle;
        if (Contains(msg, "audio") && Contains(msg, "track"))
            return PlaybackErrorCode.Track;
        if (Contains(msg, "unsupported") || Contains(msg, "codec"))
            return PlaybackErrorCode.Unsupported;
        if (Contains(msg, "cancel"))
            return PlaybackErrorCode.Cancelled;
        if (Contains(msg, "libvlc") || Contains(msg, "media foundation") || Contains(msg, "backend"))
            return PlaybackErrorCode.Backend;
        if (Contains(msg, "session") || Contains(msg, "prepare"))
            return PlaybackErrorCode.Session;
        return PlaybackErrorCode.Unknown;
    }

    private static bool Contains(string hay, string needle) =>
        hay.Contains(needle, StringComparison.OrdinalIgnoreCase);
}
