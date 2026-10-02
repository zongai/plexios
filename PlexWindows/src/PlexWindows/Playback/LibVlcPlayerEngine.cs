using Microsoft.UI.Dispatching;
using PlexWindows.Models;
#if USE_LIBVLC
using LibVLCSharp.Shared;
#endif

namespace PlexWindows.Playback;

/// <summary>
/// LibVLC backend for formats Media Foundation cannot open.
/// Requires: LibVLCSharp, LibVLCSharp.WinUI, VideoLAN.LibVLC.Windows
/// </summary>
public sealed class LibVlcPlayerEngine : IPlayerEngine
{
    private readonly DispatcherQueue _dispatcher;
    private PlayerState _state = PlayerState.Idle;
    private long _positionMs;
    private long _durationMs;
    private double _volume = 1.0;
    private bool _isMuted;
    private readonly List<TrackInfo> _audioTracks = [];
    private readonly List<TrackInfo> _subtitleTracks = [];

#if USE_LIBVLC
    private LibVLC? _libVlc;
    private MediaPlayer? _mediaPlayer;
    private Media? _media;
    private LibVLCSharp.WinUI.VideoView? _videoView;
    private long? _pendingSeekMs;
#endif

    public static bool IsAvailable
    {
        get
        {
#if USE_LIBVLC
            return true;
#else
            return false;
#endif
        }
    }

    public LibVlcPlayerEngine()
    {
        _dispatcher = DispatcherQueue.GetForCurrentThread()
                      ?? throw new InvalidOperationException("LibVlcPlayerEngine requires a UI DispatcherQueue.");
#if USE_LIBVLC
        Core.Initialize();
#endif
    }

    public PlayerBackendKind Backend => PlayerBackendKind.LibVlc;

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
    public long DurationMs => _durationMs;
    public long BufferedMs => _positionMs;

    public double Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0, 1);
#if USE_LIBVLC
            if (_mediaPlayer is not null)
                _mediaPlayer.Volume = (int)(_volume * 100);
#endif
        }
    }

    public bool IsMuted
    {
        get => _isMuted;
        set
        {
            _isMuted = value;
#if USE_LIBVLC
            if (_mediaPlayer is not null)
                _mediaPlayer.Mute = value;
#endif
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
#if USE_LIBVLC
        if (libVlcVideoView is LibVLCSharp.WinUI.VideoView vv)
        {
            _videoView = vv;
            EnsurePlayer();
            if (_mediaPlayer is not null)
                _videoView.MediaPlayer = _mediaPlayer;
        }
#else
        _ = mediaPlayerElement;
        _ = libVlcVideoView;
#endif
    }

    public async Task PrepareAsync(PlaybackRequest request, CancellationToken ct = default)
    {
        State = PlayerState.Opening;
        _durationMs = request.Metadata.Duration ?? 0;
        _positionMs = request.StartPositionMs;
        BuildTracks(request.Metadata, request.Decision);

#if !USE_LIBVLC
        State = PlayerState.Error;
        ErrorOccurred?.Invoke(this, "LibVLC was not compiled in (USE_LIBVLC undefined).");
        await Task.CompletedTask;
        return;
#else
        try
        {
            EnsurePlayer();
            if (_mediaPlayer is null || _libVlc is null)
            {
                State = PlayerState.Error;
                ErrorOccurred?.Invoke(this, "LibVLC MediaPlayer failed to initialize.");
                return;
            }

            _mediaPlayer.Stop();
            _media?.Dispose();

            _media = new Media(_libVlc, request.MediaUrl);
            _media.AddOption(":network-caching=1500");
            _media.AddOption(":file-caching=1500");
            _mediaPlayer.Media = _media;

            try
            {
                await _media.Parse(MediaParseOptions.ParseNetwork, timeout: 5000).ConfigureAwait(true);
                if (_media.Duration > 0)
                    _durationMs = _media.Duration;
            }
            catch
            {
                // LengthChanged may provide duration later
            }

            _mediaPlayer.Volume = (int)(_volume * 100);
            _mediaPlayer.Mute = _isMuted;
            _pendingSeekMs = request.StartPositionMs > 0 ? request.StartPositionMs : null;

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
            ErrorOccurred?.Invoke(this, $"LibVLC prepare failed: {ex.Message}");
        }

        await Task.CompletedTask;
#endif
    }

    public void Play()
    {
#if USE_LIBVLC
        _mediaPlayer?.Play();
#endif
        State = PlayerState.Playing;
    }

    public void Pause()
    {
#if USE_LIBVLC
        _mediaPlayer?.SetPause(true);
#endif
        State = PlayerState.Paused;
    }

    public Task StopAsync()
    {
#if USE_LIBVLC
        try
        {
            _mediaPlayer?.Stop();
            if (_mediaPlayer is not null)
                _mediaPlayer.Media = null;
            _media?.Dispose();
            _media = null;
        }
        catch { /* teardown */ }
#endif
        State = PlayerState.Stopped;
        _positionMs = 0;
        return Task.CompletedTask;
    }

    public Task SeekAsync(long positionMs, CancellationToken ct = default)
    {
        _positionMs = Math.Clamp(positionMs, 0, Math.Max(_durationMs, positionMs));
#if USE_LIBVLC
        if (_mediaPlayer is not null && _mediaPlayer.IsSeekable)
            _mediaPlayer.Time = _positionMs;
#endif
        RaiseOnUi(() => PositionChanged?.Invoke(this, EventArgs.Empty));
        return Task.CompletedTask;
    }

    public Task SelectAudioTrackAsync(int streamId, CancellationToken ct = default)
    {
        foreach (var t in _audioTracks) t.IsSelected = t.Id == streamId;
#if USE_LIBVLC
        if (_mediaPlayer is not null)
        {
            var tracks = _mediaPlayer.AudioTrackDescription;
            var idx = _audioTracks.FindIndex(a => a.Id == streamId);
            if (idx >= 0 && idx < tracks.Length)
                _mediaPlayer.SetAudioTrack(tracks[idx].Id);
        }
#endif
        RaiseOnUi(() => TracksChanged?.Invoke(this, EventArgs.Empty));
        return Task.CompletedTask;
    }

    public Task SelectSubtitleAsync(int? streamId, CancellationToken ct = default)
    {
        foreach (var t in _subtitleTracks)
            t.IsSelected = streamId is int id && t.Id == id;
#if USE_LIBVLC
        if (_mediaPlayer is not null)
        {
            if (streamId is null)
            {
                _mediaPlayer.SetSpu(-1);
            }
            else
            {
                var tracks = _mediaPlayer.SpuDescription;
                var idx = _subtitleTracks.FindIndex(s => s.Id == streamId);
                if (idx >= 0 && idx < tracks.Length)
                    _mediaPlayer.SetSpu(tracks[idx].Id);
            }
        }
#endif
        RaiseOnUi(() => TracksChanged?.Invoke(this, EventArgs.Empty));
        return Task.CompletedTask;
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync();
#if USE_LIBVLC
        if (_mediaPlayer is not null)
        {
            _mediaPlayer.Dispose();
            _mediaPlayer = null;
        }
        _libVlc?.Dispose();
        _libVlc = null;
        if (_videoView is not null)
        {
            _videoView.MediaPlayer = null;
            _videoView = null;
        }
#endif
    }

#if USE_LIBVLC
    private void EnsurePlayer()
    {
        _libVlc ??= new LibVLC("--no-osd", "--avcodec-hw=any", "--network-caching=1500");

        if (_mediaPlayer is null)
        {
            _mediaPlayer = new MediaPlayer(_libVlc);
            _mediaPlayer.Playing += (_, _) =>
            {
                State = PlayerState.Playing;
                if (_pendingSeekMs is long seek && _mediaPlayer is not null)
                {
                    _mediaPlayer.Time = seek;
                    _pendingSeekMs = null;
                }
            };
            _mediaPlayer.Paused += (_, _) => State = PlayerState.Paused;
            _mediaPlayer.Stopped += (_, _) =>
            {
                if (State != PlayerState.Ended)
                    State = PlayerState.Stopped;
            };
            _mediaPlayer.EndReached += (_, _) => State = PlayerState.Ended;
            _mediaPlayer.EncounteredError += (_, _) =>
            {
                State = PlayerState.Error;
                RaiseOnUi(() => ErrorOccurred?.Invoke(this, "LibVLC encountered a playback error."));
            };
            _mediaPlayer.Buffering += (_, e) =>
            {
                if (e.Cache < 100f)
                    State = PlayerState.Buffering;
            };
            _mediaPlayer.TimeChanged += (_, e) =>
            {
                _positionMs = e.Time;
                RaiseOnUi(() => PositionChanged?.Invoke(this, EventArgs.Empty));
            };
            _mediaPlayer.LengthChanged += (_, e) =>
            {
                if (e.Length > 0)
                    _durationMs = e.Length;
                RaiseOnUi(() => PositionChanged?.Invoke(this, EventArgs.Empty));
            };
        }

        if (_videoView is not null && !ReferenceEquals(_videoView.MediaPlayer, _mediaPlayer))
            _videoView.MediaPlayer = _mediaPlayer;
    }
#endif

    private void BuildTracks(PlexMetadata metadata, PlaybackDecision decision)
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
                Title = s.ExtendedDisplayTitle ?? s.DisplayTitle ?? s.Language ?? $"Audio {s.Id}",
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
                Title = s.ExtendedDisplayTitle ?? s.DisplayTitle ?? s.Language ?? $"Subtitle {s.Id}",
                Language = s.LanguageCode ?? s.Language,
                Codec = s.Codec ?? s.Format,
                IsSelected = decision.SelectedSubtitleStreamId == s.Id
            });
        }
    }

    private void RaiseOnUi(Action action)
    {
        if (_dispatcher.HasThreadAccess) action();
        else _dispatcher.TryEnqueue(() => action());
    }
}
