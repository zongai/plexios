using Microsoft.UI.Dispatching;
using PlexWindows.Helpers;
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
    private string? _lastLibVlcLog;
    private PlaybackRequest? _lastRequest;
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
        AppDebugLog.Info("LibVLC.Core",
            dir is null
                ? "libvlc.dll not found under BaseDirectory=" + AppContext.BaseDirectory
                : "using native dir=" + dir);

        if (dir is not null)
        {
            // Ensure plugin loader can resolve sibling DLLs
            try
            {
                var path = Environment.GetEnvironmentVariable("PATH") ?? "";
                if (!path.Split(Path.PathSeparator).Any(p =>
                        string.Equals(p, dir, StringComparison.OrdinalIgnoreCase)))
                {
                    Environment.SetEnvironmentVariable("PATH", dir + Path.PathSeparator + path);
                }
            }
            catch { /* non-fatal */ }

            Core.Initialize(dir);
        }
        else
        {
            Core.Initialize();
        }
    }
#endif

    public static bool IsAvailable
    {
        get
        {
#if USE_LIBVLC
            try
            {
                EnsureCoreInitialized();
                // Probe real native instanciation (Core.Initialize alone is not enough)
                using var probe = new LibVLC("--no-video-title-show");
                AppDebugLog.Info("LibVLC", "IsAvailable probe OK");
                return true;
            }
            catch (Exception ex)
            {
                AppDebugLog.Error("LibVLC", ex, "IsAvailable probe failed");
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
    public double Rate => _rate;
    private double _rate = 1.0;
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
        _lastRequest = request;
        BuildTracks(request.Metadata, request.Decision);

#if !USE_LIBVLC
        State = PlayerState.Error;
        ErrorOccurred?.Invoke(this, "LibVLC was not compiled in (USE_LIBVLC undefined).");
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
            AppDebugLog.Info("LibVLC.Prepare",
                $"mode={request.Decision.Mode} reason={request.Decision.Reason} url={AppDebugLog.RedactUrl(url)}");

            // PMS returns HTTP 400 when LibVLC GETs start.m3u8 with Range: bytes=0-.
            // Prefetch playlist with HttpClient (no Range) and play from a local temp file.
            if (url.Contains("start.m3u8", StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    var local = await PrefetchHlsPlaylistAsync(request.MediaUrl, ct).ConfigureAwait(true);
                    AppDebugLog.Info("LibVLC.Prepare", "playing prefetched HLS " + local);
                    _media = new Media(_libVlc, local, FromType.FromPath);
                }
                catch (Exception ex)
                {
                    AppDebugLog.Error("LibVLC.Prepare", ex, "HLS prefetch failed — trying direct URL");
                    _media = new Media(_libVlc, url, FromType.FromLocation);
                }
            }
            else
            {
                _media = new Media(_libVlc, url, FromType.FromLocation);
            }

            _media.AddOption(":network-caching=3000");
            _media.AddOption(":file-caching=3000");
            _media.AddOption(":live-caching=3000");
            _media.AddOption(":http-reconnect=true");
            _media.AddOption(":http-user-agent=PlexWindows/0.1");
            _media.AddOption(":avcodec-hw=any");

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

    public void SetRate(double rate)
    {
        _rate = Math.Clamp(rate, 0.25, 2.0);
        if (_mediaPlayer is not null)
        {
            try { _mediaPlayer.SetRate((float)_rate); }
            catch { /* ignore */ }
        }
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

    public Task SelectAudioTrackAsync(int streamId, int listIndex = -1, CancellationToken ct = default)
    {
        foreach (var t in _audioTracks) t.IsSelected = t.Id == streamId;
#if USE_LIBVLC
        if (_mediaPlayer is null)
        {
            RaiseOnUi(() => ErrorOccurred?.Invoke(this, "Audio switch failed: player not ready."));
            return Task.CompletedTask;
        }

        var raw = _mediaPlayer.AudioTrackDescription;
        var vlcIds = new List<int>();
        if (raw is not null)
        {
            foreach (var td in raw)
            {
                if (td.Id >= 0)
                    vlcIds.Add(td.Id);
            }
        }

        if (vlcIds.Count == 0)
        {
            // Tracks not exposed yet — try after a brief moment is caller's job; report clearly
            RaiseOnUi(() => ErrorOccurred?.Invoke(this,
                "Audio tracks not ready yet — wait until playback starts, then switch again."));
            return Task.CompletedTask;
        }

        int? target = null;
        // Prefer ComboBox list index (same order as Plex streams we published)
        if (listIndex >= 0 && listIndex < vlcIds.Count)
            target = vlcIds[listIndex];
        else
        {
            var idx = _audioTracks.FindIndex(a => a.Id == streamId);
            if (idx >= 0 && idx < vlcIds.Count)
                target = vlcIds[idx];
        }

        if (target is int vlcId)
        {
            var ok = _mediaPlayer.SetAudioTrack(vlcId);
            var current = _mediaPlayer.AudioTrack;
            if (!ok && current != vlcId)
            {
                RaiseOnUi(() => ErrorOccurred?.Invoke(this,
                    $"SetAudioTrack({vlcId}) failed (index={listIndex}, plexId={streamId}, current={current})."));
            }
        }
        else
        {
            RaiseOnUi(() => ErrorOccurred?.Invoke(this,
                $"No VLC audio track for plexId={streamId} index={listIndex} (vlcCount={vlcIds.Count})."));
        }
#endif
        return Task.CompletedTask;
    }

    public Task SelectSubtitleAsync(int? streamId, CancellationToken ct = default)
    {
        foreach (var t in _subtitleTracks)
            t.IsSelected = streamId is int id && t.Id == id;
#if USE_LIBVLC
        if (_mediaPlayer is null)
            return Task.CompletedTask;

        if (streamId is null)
        {
            _mediaPlayer.SetSpu(-1);
            return Task.CompletedTask;
        }

        // External sidecar: load via AddSlave from PMS stream key
        var plexMeta = _lastRequest?.Metadata;
        var decision = _lastRequest?.Decision;
        var mi = decision?.MediaIndex ?? 0;
        var pi = decision?.PartIndex ?? 0;
        var part = plexMeta?.Media is { Count: > 0 } mediaList
            ? mediaList.ElementAtOrDefault(Math.Clamp(mi, 0, mediaList.Count - 1))
            : null;
        var partObj = part?.Parts is { Count: > 0 } parts
            ? parts.ElementAtOrDefault(Math.Clamp(pi, 0, parts.Count - 1))
            : null;
        var plexStream = partObj?.Streams?.FirstOrDefault(s =>
            s.Type == PlexStream.StreamType.Subtitle && s.Id == streamId);
        if (plexStream?.IsExternal == true && !string.IsNullOrEmpty(plexStream.Key)
            && _lastRequest?.Context is { } ctx)
        {
            try
            {
                var path = plexStream.Key.TrimStart('/');
                var subUri = new Uri(ctx.BaseUrl, path);
                var ub = new UriBuilder(subUri)
                {
                    Query = "X-Plex-Token=" + Uri.EscapeDataString(ctx.Token)
                };
                // select=true makes this the active subtitle
                _mediaPlayer.AddSlave(MediaSlaveType.Subtitle, ub.Uri.AbsoluteUri, select: true);
                return Task.CompletedTask;
            }
            catch (Exception ex)
            {
                RaiseOnUi(() => ErrorOccurred?.Invoke(this, "External subtitle failed: " + ex.Message));
            }
        }

        // Embedded: map list index / language to VLC SPU id
        var rawSpu = _mediaPlayer.SpuDescription;
        var vlcTracks = rawSpu is null
            ? Array.Empty<(int Id, string? Name)>()
            : rawSpu.Where(td => td.Id >= 0).Select(td => (td.Id, td.Name)).ToArray();
        if (vlcTracks.Length == 0)
        {
            RaiseOnUi(() => ErrorOccurred?.Invoke(this,
                "Subtitle tracks not ready yet — wait for playback, or use session rebuild."));
            return Task.CompletedTask;
        }

        int? matchId = null;
        var plex = _subtitleTracks.FirstOrDefault(s => s.Id == streamId);
        if (plex is not null)
        {
            var lang = plex.Language?.Trim();
            var title = plex.Title?.Trim();
            if (!string.IsNullOrEmpty(lang))
            {
                var m = vlcTracks.FirstOrDefault(v =>
                    !string.IsNullOrEmpty(v.Name) &&
                    v.Name.Contains(lang, StringComparison.OrdinalIgnoreCase));
                if (m.Name is not null) matchId = m.Id;
            }
            if (matchId is null && !string.IsNullOrEmpty(title))
            {
                var token = title.Split(' ', StringSplitOptions.RemoveEmptyEntries).FirstOrDefault();
                if (!string.IsNullOrEmpty(token) && token.Length >= 2)
                {
                    var m = vlcTracks.FirstOrDefault(v =>
                        !string.IsNullOrEmpty(v.Name) &&
                        v.Name.Contains(token, StringComparison.OrdinalIgnoreCase));
                    if (m.Name is not null) matchId = m.Id;
                }
            }
        }
        if (matchId is null)
        {
            var idx = _subtitleTracks.FindIndex(s => s.Id == streamId);
            if (idx >= 0 && idx < vlcTracks.Length)
                matchId = vlcTracks[idx].Id;
        }
        if (matchId is int spuId)
        {
            try { _mediaPlayer.SetSpu(spuId); }
            catch (Exception ex)
            {
                RaiseOnUi(() => ErrorOccurred?.Invoke(this, "SetSpu failed: " + ex.Message));
            }
        }
#endif
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
                // Only pass options that LibVLCWinUI sample uses (swapchain + quiet UI)
                _libVlc = new LibVLC(enableDebugLogs: true, opts.ToArray());
                _libVlc.Log += (_, e) =>
                {
                    if (e.Level is LogLevel.Error or LogLevel.Warning)
                    {
                        _lastLibVlcLog = $"[{e.Level}] {e.Module}: {e.Message}";
                        AppDebugLog.Warn("LibVLC", $"{e.Module}: {e.Message}");
                    }
                    else if (e.Level == LogLevel.Debug)
                    {
                        AppDebugLog.Info("LibVLC", $"{e.Module}: {e.Message}");
                    }
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
            // Minimal, known-good options only. Unknown switches crash native init.
            AppDebugLog.Info("LibVLC", "Creating LibVLC instance…");
            try
            {
                _libVlc = new LibVLC(
                    enableDebugLogs: true,
                    "--no-video-title-show",
                    "--network-caching=3000");
            }
            catch (Exception ex)
            {
                AppDebugLog.Error("LibVLC", ex, "new LibVLC() failed");
                throw;
            }
            _libVlc.Log += (_, e) =>
            {
                if (e.Level is LogLevel.Error or LogLevel.Warning)
                {
                    _lastLibVlcLog = $"[{e.Level}] {e.Module}: {e.Message}";
                    AppDebugLog.Warn("LibVLC", $"{e.Module}: {e.Message}");
                }
            };
            AppDebugLog.Info("LibVLC", "LibVLC instance OK");
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
                AppDebugLog.Error("LibVLC", "EncounteredError: " + detail + " url=" + AppDebugLog.RedactUrl(_lastRequest?.MediaUrl?.AbsoluteUri));
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
                IsSelected = decision.SelectedAudioStreamId == s.Id,
                IsDefault = s.IsDefault,
                IsForced = s.IsForced,
                IsExternal = s.IsExternal,
                Type = "audio"
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
                IsSelected = decision.SelectedSubtitleStreamId == s.Id,
                IsDefault = s.IsDefault,
                IsForced = s.IsForced,
                IsExternal = s.IsExternal,
                Type = "subtitle"
            });
        }
    }

    private void RaiseOnUi(Action action)
    {
        if (_dispatcher.HasThreadAccess) action();
        else _dispatcher.TryEnqueue(() => action());
    }
}
