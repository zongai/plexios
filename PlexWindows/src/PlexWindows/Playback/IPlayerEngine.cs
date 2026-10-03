namespace PlexWindows.Playback;

/// <summary>
/// Contract-aligned states (docs/cross-platform-playback-contract.md §4).
/// Mapping: Opening → loading; other names match the contract 1:1.
/// Buffering is NOT paused — UI play/pause follows play intent.
/// </summary>
public enum PlayerState
{
    Idle,
    Opening,   // contract: loading
    Buffering,
    Playing,
    Paused,
    Stopped,
    Ended,
    Error
}

public enum PlayerBackendKind
{
    MediaFoundation,
    LibVlc
}

public sealed class PlaybackRequest
{
    public required Models.PlexMetadata Metadata { get; init; }
    public required Models.ServerContext Context { get; init; }
    public required NetworkClass Network { get; init; }
    public required PlaybackDecision Decision { get; init; }
    public required Uri MediaUrl { get; init; }
    public long StartPositionMs { get; init; }
    public PlaybackPreferences Preferences { get; init; } = PlaybackPreferences.Default;
}

/// <summary>
/// Unified player surface for Windows backends (Media Foundation, LibVLC).
/// </summary>
public interface IPlayerEngine : IAsyncDisposable
{
    PlayerState State { get; }
    PlayerBackendKind Backend { get; }
    long PositionMs { get; }
    long DurationMs { get; }
    long BufferedMs { get; }
    double Volume { get; set; }
    bool IsMuted { get; set; }

    IReadOnlyList<TrackInfo> AudioTracks { get; }
    IReadOnlyList<TrackInfo> SubtitleTracks { get; }

    /// <summary>
    /// Attach platform surfaces. MF uses MediaPlayerElement; LibVLC uses VideoView.
    /// </summary>
    void AttachSurfaces(object? mediaPlayerElement, object? libVlcVideoView);

    event EventHandler<PlayerState>? StateChanged;
    event EventHandler? PositionChanged;
    event EventHandler<string>? ErrorOccurred;
    event EventHandler? TracksChanged;
    event EventHandler<PlayerBackendKind>? BackendChanged;

    Task PrepareAsync(PlaybackRequest request, CancellationToken ct = default);
    void Play();
    void Pause();
    Task StopAsync();
    Task SeekAsync(long positionMs, CancellationToken ct = default);
    Task SelectAudioTrackAsync(int streamId, int listIndex = -1, CancellationToken ct = default);
    Task SelectSubtitleAsync(int? streamId, CancellationToken ct = default);
}
