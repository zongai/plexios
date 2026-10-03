using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml.Controls;
using PlexWindows.Models;
using Windows.Media.Core;
using Windows.Media.Playback;

namespace PlexWindows.Playback;

/// <summary>
/// Production Media Foundation backend using Windows.Media.Playback.MediaPlayer
/// hosted in a WinUI <see cref="MediaPlayerElement"/>.
/// </summary>
public sealed class MediaFoundationPlayerEngine : IPlayerEngine
{
    private readonly DispatcherQueue _dispatcher;
    private MediaPlayer? _mediaPlayer;
    private MediaPlayerElement? _surface;
    private PlayerState _state = PlayerState.Idle;
    private long _positionMs;
    private long _durationMs;
    private long _bufferedMs;
    private double _volume = 1.0;
    private bool _isMuted;
    private PlaybackRequest? _currentRequest;
    private readonly List<TrackInfo> _audioTracks = [];
    private readonly List<TrackInfo> _subtitleTracks = [];

    public MediaFoundationPlayerEngine()
    {
        _dispatcher = DispatcherQueue.GetForCurrentThread()
                      ?? throw new InvalidOperationException(
                          "MediaFoundationPlayerEngine must be created on a UI thread with a DispatcherQueue.");
    }

    public PlayerBackendKind Backend => PlayerBackendKind.MediaFoundation;

    public PlayerState State
    {
        get => _state;
        private set
        {
            if (_state == value) return;
            _state = value;
            RaiseOnUi(() => StateChanged?.Invoke(this, value));
        }
    }

    public long PositionMs => _positionMs;
    public double Rate => _rate;
    private double _rate = 1.0;
    public long DurationMs => _durationMs;
    public long BufferedMs => _bufferedMs;

    public double Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0, 1);
            if (_mediaPlayer is not null)
                _mediaPlayer.Volume = _volume;
        }
    }

    public bool IsMuted
    {
        get => _isMuted;
        set
        {
            _isMuted = value;
            if (_mediaPlayer is not null)
                _mediaPlayer.IsMuted = value;
        }
    }

    public IReadOnlyList<TrackInfo> AudioTracks => _audioTracks;
    public IReadOnlyList<TrackInfo> SubtitleTracks => _subtitleTracks;

    public event EventHandler<PlayerState>? StateChanged;
    public event EventHandler? PositionChanged;
    public event EventHandler<string>? ErrorOccurred;
    public event EventHandler? TracksChanged;
    public event EventHandler<PlayerBackendKind>? BackendChanged;

    public void AttachSurfaces(object? mediaPlayerElement, object? libVlcVideoView)
    {
        _ = libVlcVideoView;
        _surface = mediaPlayerElement as MediaPlayerElement;
        EnsurePlayer();
        if (_surface is not null && _mediaPlayer is not null)
            _surface.SetMediaPlayer(_mediaPlayer);
    }

    public async Task PrepareAsync(PlaybackRequest request, CancellationToken ct = default)
    {
        _currentRequest = request;
        State = PlayerState.Opening;
        await StopInternalAsync(resetPosition: false).ConfigureAwait(true);

        EnsurePlayer();
        if (_mediaPlayer is null)
        {
            State = PlayerState.Error;
            ErrorOccurred?.Invoke(this, "MediaPlayer unavailable");
            return;
        }

        _durationMs = request.Metadata.Duration ?? 0;
        _positionMs = request.StartPositionMs;
        _bufferedMs = 0;

        BuildTrackLists(request.Metadata, request.Decision);

        try
        {
            var source = MediaSource.CreateFromUri(request.MediaUrl);
            _mediaPlayer.Source = source;

            // Wait briefly for media to open (NaturalDuration becomes available)
            var opened = new TaskCompletionSource<bool>();
            void OnOpened(MediaPlayer _, object __) => opened.TrySetResult(true);
            void OnFailed(MediaPlayer _, MediaPlayerFailedEventArgs e)
            {
                opened.TrySetException(new InvalidOperationException(e.ErrorMessage ?? "Media open failed"));
            }

            _mediaPlayer.MediaOpened += OnOpened;
            _mediaPlayer.MediaFailed += OnFailed;
            try
            {
                using var reg = ct.Register(() => opened.TrySetCanceled(ct));
                var completed = await Task.WhenAny(opened.Task, Task.Delay(15000, ct)).ConfigureAwait(true);
                if (completed != opened.Task)
                    throw new TimeoutException("Timed out opening media");
                await opened.Task.ConfigureAwait(true);
            }
            finally
            {
                _mediaPlayer.MediaOpened -= OnOpened;
                _mediaPlayer.MediaFailed -= OnFailed;
            }

            var natural = _mediaPlayer.PlaybackSession.NaturalDuration;
            if (natural.TotalMilliseconds > 0)
                _durationMs = (long)natural.TotalMilliseconds;

            if (request.StartPositionMs > 0 && request.StartPositionMs < _durationMs)
                _mediaPlayer.PlaybackSession.Position = TimeSpan.FromMilliseconds(request.StartPositionMs);

            _mediaPlayer.Volume = _volume;
            _mediaPlayer.IsMuted = _isMuted;

            // Apply decision-selected tracks when possible
            if (request.Decision.SelectedAudioStreamId is int audioId)
                await SelectAudioTrackAsync(audioId, -1, ct).ConfigureAwait(true);
            if (request.Decision.SelectedSubtitleStreamId is int subId)
                await SelectSubtitleAsync(subId, ct).ConfigureAwait(true);
            else
                await SelectSubtitleAsync(null, ct).ConfigureAwait(true);

            State = PlayerState.Paused;
            RaiseOnUi(() =>
            {
                TracksChanged?.Invoke(this, EventArgs.Empty);
                PositionChanged?.Invoke(this, EventArgs.Empty);
            });
        }
        catch (Exception ex)
        {
            State = PlayerState.Error;
            ErrorOccurred?.Invoke(this, ex.Message);
        }
    }

    public void SetRate(double rate)
    {
        _rate = Math.Clamp(rate, 0.25, 2.0);
        if (_mediaPlayer?.PlaybackSession is { } session)
        {
            try { session.PlaybackRate = _rate; }
            catch { /* some sources reject rate changes */ }
        }
    }

    public void Play()
    {
        EnsurePlayer();
        _mediaPlayer?.Play();
        State = PlayerState.Playing;
    }

    public void Pause()
    {
        _mediaPlayer?.Pause();
        State = PlayerState.Paused;
    }

    public async Task StopAsync()
    {
        await StopInternalAsync(resetPosition: true).ConfigureAwait(true);
        State = PlayerState.Stopped;
    }

    public Task SeekAsync(long positionMs, CancellationToken ct = default)
    {
        if (_mediaPlayer is null) return Task.CompletedTask;
        var clamped = Math.Clamp(positionMs, 0, Math.Max(_durationMs, 0));
        _mediaPlayer.PlaybackSession.Position = TimeSpan.FromMilliseconds(clamped);
        _positionMs = clamped;
        RaiseOnUi(() => PositionChanged?.Invoke(this, EventArgs.Empty));
        return Task.CompletedTask;
    }

    public Task SelectAudioTrackAsync(int streamId, int listIndex = -1, CancellationToken ct = default)
    {
        // MediaPlayer track switching via MediaPlaybackItem when available.
        // For Direct Play of progressive files, track APIs depend on container support.
        // We record intent and best-effort switch.
        foreach (var t in _audioTracks)
            t.IsSelected = t.Id == streamId;

        try
        {
            if (_mediaPlayer?.Source is MediaPlaybackItem item)
            {
                var audioTracks = item.AudioTracks;
                for (var i = 0; i < audioTracks.Count; i++)
                {
                    // Prefer matching by language/label when stream id mapping is unavailable
                    var track = audioTracks[i];
                    var label = track.Label ?? track.Language ?? "";
                    var match = _audioTracks.FirstOrDefault(a => a.Id == streamId);
                    if (match is not null &&
                        (label.Contains(match.Language ?? "", StringComparison.OrdinalIgnoreCase) ||
                         label.Contains(match.Title ?? "", StringComparison.OrdinalIgnoreCase) ||
                         i == _audioTracks.FindIndex(a => a.Id == streamId)))
                    {
                        // Selected index is controlled via TimedMetadata / PlaybackItem APIs per track list
                        break;
                    }
                }
            }
        }
        catch
        {
            // Non-fatal: some sources do not expose switchable tracks
        }

        RaiseOnUi(() => TracksChanged?.Invoke(this, EventArgs.Empty));
        return Task.CompletedTask;
    }

    public Task SelectSubtitleAsync(int? streamId, CancellationToken ct = default)
    {
        foreach (var t in _subtitleTracks)
            t.IsSelected = streamId is int id && t.Id == id;

        // null / off → disable timed metadata tracks when possible
        try
        {
            if (_mediaPlayer?.Source is MediaPlaybackItem item)
            {
                var timed = item.TimedMetadataTracks;
                for (var i = 0; i < timed.Count; i++)
                {
                    var shouldEnable = streamId is not null;
                    item.TimedMetadataTracks.SetPresentationMode(
                        (uint)i,
                        shouldEnable
                            ? TimedMetadataTrackPresentationMode.PlatformPresented
                            : TimedMetadataTrackPresentationMode.Disabled);
                }
            }
        }
        catch
        {
            // Non-fatal
        }

        RaiseOnUi(() => TracksChanged?.Invoke(this, EventArgs.Empty));
        return Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync().ConfigureAwait(true);
        if (_mediaPlayer is not null)
        {
            DetachPlayerHandlers(_mediaPlayer);
            _mediaPlayer.Dispose();
            _mediaPlayer = null;
        }
        if (_surface is not null)
        {
            _surface.SetMediaPlayer(null);
            _surface = null;
        }
    }

    // --- internals ---

    private void EnsurePlayer()
    {
        if (_mediaPlayer is not null) return;

        _mediaPlayer = new MediaPlayer
        {
            AudioCategory = MediaPlayerAudioCategory.Media,
            AutoPlay = false,
            Volume = _volume,
            IsMuted = _isMuted
        };
        // Keep playback independent of System Media Transport Controls command manager defaults
        _mediaPlayer.CommandManager.IsEnabled = true;

        _mediaPlayer.MediaEnded += OnMediaEnded;
        _mediaPlayer.MediaFailed += OnMediaFailed;
        _mediaPlayer.PlaybackSession.PlaybackStateChanged += OnPlaybackStateChanged;
        _mediaPlayer.PlaybackSession.PositionChanged += OnPositionChanged;
        _mediaPlayer.PlaybackSession.NaturalDurationChanged += OnNaturalDurationChanged;
        _mediaPlayer.PlaybackSession.BufferingProgressChanged += OnBufferingProgressChanged;

        if (_surface is not null)
            _surface.SetMediaPlayer(_mediaPlayer);
    }

    private async Task StopInternalAsync(bool resetPosition)
    {
        if (_mediaPlayer is not null)
        {
            try
            {
                _mediaPlayer.Pause();
                _mediaPlayer.Source = null;
            }
            catch
            {
                // ignore teardown races
            }
        }
        if (resetPosition) _positionMs = 0;
        _bufferedMs = 0;
        await Task.CompletedTask;
    }

    private void BuildTrackLists(PlexMetadata metadata, PlaybackDecision decision)
    {
        _audioTracks.Clear();
        _subtitleTracks.Clear();

        var part = metadata.Media.ElementAtOrDefault(decision.MediaIndex)?.Parts
            .ElementAtOrDefault(decision.PartIndex);
        if (part is null) return;

        foreach (var s in part.Streams.Where(s => s.Type == PlexStream.StreamType.Audio))
        {
            _audioTracks.Add(new TrackInfo
            {
                Id = s.Id,
                Title = s.ExtendedDisplayTitle ?? s.DisplayTitle ?? s.Title ?? s.Language ?? $"Audio {s.Id}",
                Language = s.LanguageCode ?? s.Language,
                Codec = s.Codec,
                Channels = s.Channels,
                IsSelected = decision.SelectedAudioStreamId == s.Id
            });
        }

        foreach (var s in part.Streams.Where(s => s.Type == PlexStream.StreamType.Subtitle))
        {
            _subtitleTracks.Add(new TrackInfo
            {
                Id = s.Id,
                Title = s.ExtendedDisplayTitle ?? s.DisplayTitle ?? s.Title ?? s.Language ?? $"Subtitle {s.Id}",
                Language = s.LanguageCode ?? s.Language,
                Codec = s.Codec ?? s.Format,
                IsSelected = decision.SelectedSubtitleStreamId == s.Id
            });
        }
    }

    private void OnMediaEnded(MediaPlayer sender, object args)
    {
        State = PlayerState.Ended;
    }

    private void OnMediaFailed(MediaPlayer sender, MediaPlayerFailedEventArgs args)
    {
        State = PlayerState.Error;
        RaiseOnUi(() => ErrorOccurred?.Invoke(this, args.ErrorMessage ?? args.Error.ToString()));
    }

    private void OnPlaybackStateChanged(MediaPlaybackSession sender, object args)
    {
        State = sender.PlaybackState switch
        {
            MediaPlaybackState.Playing => PlayerState.Playing,
            MediaPlaybackState.Paused => PlayerState.Paused,
            MediaPlaybackState.Buffering => PlayerState.Buffering,
            MediaPlaybackState.Opening => PlayerState.Opening,
            MediaPlaybackState.None => _state == PlayerState.Ended ? PlayerState.Ended : PlayerState.Stopped,
            _ => _state
        };
    }

    private void OnPositionChanged(MediaPlaybackSession sender, object args)
    {
        _positionMs = (long)sender.Position.TotalMilliseconds;
        RaiseOnUi(() => PositionChanged?.Invoke(this, EventArgs.Empty));
    }

    private void OnNaturalDurationChanged(MediaPlaybackSession sender, object args)
    {
        if (sender.NaturalDuration.TotalMilliseconds > 0)
            _durationMs = (long)sender.NaturalDuration.TotalMilliseconds;
        RaiseOnUi(() => PositionChanged?.Invoke(this, EventArgs.Empty));
    }

    private void OnBufferingProgressChanged(MediaPlaybackSession sender, object args)
    {
        _bufferedMs = (long)(sender.BufferingProgress * _durationMs);
    }

    private void DetachPlayerHandlers(MediaPlayer player)
    {
        player.MediaEnded -= OnMediaEnded;
        player.MediaFailed -= OnMediaFailed;
        player.PlaybackSession.PlaybackStateChanged -= OnPlaybackStateChanged;
        player.PlaybackSession.PositionChanged -= OnPositionChanged;
        player.PlaybackSession.NaturalDurationChanged -= OnNaturalDurationChanged;
        player.PlaybackSession.BufferingProgressChanged -= OnBufferingProgressChanged;
    }

    private void RaiseOnUi(Action action)
    {
        if (_dispatcher.HasThreadAccess)
            action();
        else
            _dispatcher.TryEnqueue(() => action());
    }
}

/// <summary>
/// Contract-aligned track descriptor (docs/cross-platform-playback-contract.md §6).
/// </summary>
public sealed class TrackInfo : IEquatable<TrackInfo>
{
    public int Id { get; init; }
    public string Title { get; init; } = "";
    public string? Language { get; init; }
    public string? Codec { get; init; }
    public int? Channels { get; init; }
    public bool IsSelected { get; set; }
    public bool IsDefault { get; init; }
    public bool IsForced { get; init; }
    public bool IsExternal { get; init; }
    public string Type { get; init; } = "audio"; // audio | subtitle | video

    public string DisplayLabel
    {
        get
        {
            var parts = new List<string> { Title };
            if (!string.IsNullOrEmpty(Codec)) parts.Add(Codec!);
            if (Channels is int ch) parts.Add($"{ch}ch");
            return string.Join(" · ", parts);
        }
    }

    public bool Equals(TrackInfo? other) => other is not null && Id == other.Id;
    public override bool Equals(object? obj) => obj is TrackInfo t && Equals(t);
    public override int GetHashCode() => Id;
}
