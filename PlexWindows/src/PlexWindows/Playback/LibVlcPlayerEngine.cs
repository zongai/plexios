using Microsoft.UI.Dispatching;
using PlexWindows.Models;
#if USE_LIBVLC
using LibVLCSharp.Shared;
#endif

namespace PlexWindows.Playback;

/// <summary>
/// LibVLCSharp backend (https://github.com/videolan/libvlcsharp).
/// Primary fallback when Media Foundation cannot open the stream.
/// Requires: LibVLCSharp, LibVLCSharp.WinUI, VideoLAN.LibVLC.Windows.
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
    private LibVLCSharp.Platforms.Windows.VideoView? _videoView;
    private long? _pendingSeekMs;
    private bool _coreReady;
#endif


#if USE_LIBVLC
    private static string? ResolveLibVlcDirectory()
    {
        var baseDir = AppContext.BaseDirectory;
        var candidates = new[]
        {
            Path.Combine(baseDir, "libvlc", "win-x64"),
            Path.Combine(baseDir, "libvlc", "x64"),
            Path.Combine(baseDir, "libvlc"),
            baseDir
        };
        foreach (var dir in candidates)
        {
            if (File.Exists(Path.Combine(dir, "libvlc.dll")))
                return dir;
        }
        return null;
    }

    private static void EnsureCoreInitialized()
    {
        var dir = ResolveLibVlcDirectory();
        if (dir is not null)
            Core.Initialize(dir);
        else
            Core.Initialize(); // last resort
    }
#endif

    public static bool IsAvailable
    {
        get
        {
#if USE_LIBVLC
            try
            {
                // Loads native libvlc from VideoLAN.LibVLC.Windows package output
                EnsureCoreInitialized();
                return true;
            }
            catch
            {
                return false;
            }
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
        try
        {
            EnsureCoreInitialized();
            _coreReady = true;
        }
        catch
        {
            _coreReady = false;
        }
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
        if (libVlcVideoView is LibVLCSharp.Platforms.Windows.VideoView vv)
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
        if (!_coreReady)
        {
            try
            {
                EnsureCoreInitialized();
                _coreReady = true;
            }
            catch (Exception ex)
            {
                State = PlayerState.Error;
                ErrorOccurred?.Invoke(this, "LibVLC native libraries failed to load: " + ex.Message);
                return;
            }
        }

        try
        {
            EnsurePlayer();
            if (_mediaPlayer is null || _libVlc is null)
            {
                State = PlayerState.Error;
                ErrorOccurred?.Invoke(this, "LibVLC MediaPlayer failed to initialize.");
                return;
            }

            // Bind surface before play (required for video output)
            if (_videoView is not null)
                _videoView.MediaPlayer = _mediaPlayer;

            _mediaPlayer.Stop();
            _media?.Dispose();

            // Network / PMS URLs must use FromLocation
            var url = request.MediaUrl.AbsoluteUri;
            _media = new Media(_libVlc, url, FromType.FromLocation);
            _media.AddOption(":network-caching=2000");
            _media.AddOption(":http-reconnect=true");
            _media.AddOption(":http-continuous=true");
            // Self-signed / local PMS certs
            _media.AddOption(":http-user-agent=PlexWindows/0.1");
            // Prefer hardware decode when available
            _media.AddOption(":avcodec-hw=any");
            // Live / HLS resilience

            _mediaPlayer.Media = _media;
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
            ErrorOccurred?.Invoke(this, "LibVLC prepare failed: " + ex.Message);
        }

        await Task.CompletedTask;
#endif
    }

    public void Play()
    {
#if USE_LIBVLC
        if (_mediaPlayer is null)
        {
            State = PlayerState.Error;
            ErrorOccurred?.Invoke(this, "LibVLC player not ready.");
            return;
        }
        if (_videoView is not null && _videoView.MediaPlayer != _mediaPlayer)
            _videoView.MediaPlayer = _mediaPlayer;
        _mediaPlayer.Play();
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
        else
            _pendingSeekMs = _positionMs;
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
            // Prefer matching by description index from Plex-ordered tracks
            var tracks = _mediaPlayer.AudioTrackDescription;
            var idx = _audioTracks.FindIndex(a => a.Id == streamId);
            // LibVLC track list often has a leading "Disable" entry
            if (tracks is { Length: > 0 })
            {
                // Try by index into non-disable tracks
                var mediaTracks = tracks.Where(t => t.Id >= 0).ToArray();
                if (idx >= 0 && idx < mediaTracks.Length)
                    _mediaPlayer.SetAudioTrack(mediaTracks[idx].Id);
            }
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
                if (tracks is { Length: > 0 })
                {
                    var mediaTracks = tracks.Where(t => t.Id >= 0).ToArray();
                    if (idx >= 0 && idx < mediaTracks.Length)
                        _mediaPlayer.SetSpu(mediaTracks[idx].Id);
                    else if (mediaTracks.Length > 0)
                        _mediaPlayer.SetSpu(mediaTracks[0].Id);
                }
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
        try
        {
            if (_videoView is not null)
                _videoView.MediaPlayer = null;
            _mediaPlayer?.Dispose();
            _mediaPlayer = null;
            _libVlc?.Dispose();
            _libVlc = null;
        }
        catch { /* ignore */ }
#endif
        await Task.CompletedTask;
    }

#if USE_LIBVLC
    /// <summary>
    /// WinUI VideoView provides SwapChainOptions on Initialized — pass them when available.
    /// </summary>
    public void OnVideoViewInitialized(string[]? swapChainOptions)
    {
#if USE_LIBVLC
        try
        {
            if (!_coreReady)
            {
                EnsureCoreInitialized();
                _coreReady = true;
            }
            // Recreate LibVLC with swap chain options when the view becomes ready
            if (swapChainOptions is { Length: > 0 })
            {
                var opts = new List<string>(swapChainOptions)
                {
                    "--no-video-title-show",
                    "--network-caching=1500"
                };
                _mediaPlayer?.Stop();
                _mediaPlayer?.Dispose();
                _mediaPlayer = null;
                _libVlc?.Dispose();
                _libVlc = new LibVLC(enableDebugLogs: false, opts.ToArray());
                _libVlc.Log += (_, e) =>
                {
                    if (e.Level is LogLevel.Error or LogLevel.Warning)
                        _lastLibVlcLog = $"[{e.Level}] {e.Module}: {e.Message}";
                };
            }
            EnsurePlayer();
            if (_videoView is not null && _mediaPlayer is not null)
                _videoView.MediaPlayer = _mediaPlayer;
        }
        catch (Exception ex)
        {
            ErrorOccurred?.Invoke(this, "LibVLC VideoView init failed: " + ex.Message);
        }
#endif
    }

    private void EnsurePlayer()
    {
        if (_libVlc is null)
        {
            // Fallback without swapchain (may still work for audio / some builds)
            _libVlc = new LibVLC(
                enableDebugLogs: false,
                "--no-video-title-show",
                "--network-caching=2000",
                "--avcodec-hw=any");
            _libVlc.Log += (_, e) =>
            {
                if (e.Level is LogLevel.Error or LogLevel.Warning)
                    _lastLibVlcLog = $"[{e.Level}] {e.Module}: {e.Message}";
            };
        }

        if (_mediaPlayer is null)
        {
            _mediaPlayer = new MediaPlayer(_libVlc);
            _mediaPlayer.TimeChanged += (_, e) =>
            {
                _positionMs = e.Time;
                RaiseOnUi(() => PositionChanged?.Invoke(this, EventArgs.Empty));
            };
            _mediaPlayer.LengthChanged += (_, e) =>
            {
                if (e.Length > 0) _durationMs = e.Length;
            };
            _mediaPlayer.Playing += (_, _) =>
            {
                State = PlayerState.Playing;
                if (_pendingSeekMs is long seek && seek > 0)
                {
                    _mediaPlayer.Time = seek;
                    _pendingSeekMs = null;
                }
            };
            _mediaPlayer.Paused += (_, _) => State = PlayerState.Paused;
            _mediaPlayer.Stopped += (_, _) => State = PlayerState.Stopped;
            _mediaPlayer.EndReached += (_, _) => State = PlayerState.Ended;
            _mediaPlayer.EncounteredError += (_, _) =>
            {
                State = PlayerState.Error;
                var detail = _lastLibVlcLog ?? "unknown";
                RaiseOnUi(() => ErrorOccurred?.Invoke(this, "LibVLC playback error: " + detail));
            };
            _mediaPlayer.Buffering += (_, e) =>
            {
                if (e.Cache < 100)
                    State = PlayerState.Buffering;
                else if (State == PlayerState.Buffering)
                    State = PlayerState.Playing;
            };
        }

        if (_videoView is not null)
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

    private void RaiseOnUi(Action action)
    {
        if (_dispatcher.HasThreadAccess) action();
        else _dispatcher.TryEnqueue(() => action());
    }
}
