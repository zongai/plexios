namespace PlexWindows.Playback;

/// <summary>
/// Routes to Media Foundation and/or LibVLC based on settings preference and open success.
/// Preferred: auto | mediaFoundation | libVlc
/// </summary>
public sealed class PlayerEngineRouter : IPlayerEngine
{
    private readonly MediaFoundationPlayerEngine _mf;
    private readonly LibVlcPlayerEngine? _vlc;
    private IPlayerEngine _active;
    private object? _mfSurface;
    private object? _vlcSurface;
    private string _preferredBackend = "auto";

    public PlayerEngineRouter(string preferredBackend = "auto")
    {
        _preferredBackend = Normalize(preferredBackend);
        _mf = new MediaFoundationPlayerEngine();
        _vlc = LibVlcPlayerEngine.IsAvailable ? new LibVlcPlayerEngine() : null;
        _active = _mf;
        Wire(_mf);
        if (_vlc is not null) Wire(_vlc);
    }

    public void SetPreferredBackend(string preferred)
    {
        _preferredBackend = Normalize(preferred);
    }

    public PlayerBackendKind Backend => _active.Backend;
    public PlayerState State => _active.State;
    public long PositionMs => _active.PositionMs;
    public long DurationMs => _active.DurationMs;
    public long BufferedMs => _active.BufferedMs;

    public double Volume
    {
        get => _active.Volume;
        set
        {
            _mf.Volume = value;
            if (_vlc is not null) _vlc.Volume = value;
        }
    }

    public bool IsMuted
    {
        get => _active.IsMuted;
        set
        {
            _mf.IsMuted = value;
            if (_vlc is not null) _vlc.IsMuted = value;
        }
    }

    public IReadOnlyList<TrackInfo> AudioTracks => _active.AudioTracks;
    public IReadOnlyList<TrackInfo> SubtitleTracks => _active.SubtitleTracks;

    public event EventHandler<PlayerState>? StateChanged;
    public event EventHandler? PositionChanged;
    public event EventHandler<string>? ErrorOccurred;
    public event EventHandler? TracksChanged;
    public event EventHandler<PlayerBackendKind>? BackendChanged;

    public void NotifyVlcViewInitialized(string[]? swapChainOptions)
    {
        _vlc?.OnVideoViewInitialized(swapChainOptions);
    }

    public void AttachSurfaces(object? mediaPlayerElement, object? libVlcVideoView)
    {
        _mfSurface = mediaPlayerElement;
        _vlcSurface = libVlcVideoView;
        _mf.AttachSurfaces(mediaPlayerElement, null);
        _vlc?.AttachSurfaces(null, libVlcVideoView);
    }

    public async Task PrepareAsync(PlaybackRequest request, CancellationToken ct = default)
    {
        // Forced LibVLC
        if (_preferredBackend == "libvlc")
        {
            if (_vlc is null)
            {
                ErrorOccurred?.Invoke(this,
                    "LibVLC is not available. Ensure VideoLAN.LibVLC.Windows native libraries are next to the exe.");
                return;
            }
            await _mf.StopAsync().ConfigureAwait(true);
            SetActive(_vlc);
            _vlc.AttachSurfaces(null, _vlcSurface);
            await _vlc.PrepareAsync(request, ct).ConfigureAwait(true);
            return;
        }

        // Auto: prefer LibVLC for Direct Stream / Transcode (PMS network URLs).
        // MF is unreliable for container-remux and many HLS edge cases.
        var preferVlc =
            _preferredBackend == "auto"
            && _vlc is not null
            && request.Decision.Mode is PlaybackMode.DirectStream or PlaybackMode.Transcode;

        if (preferVlc)
        {
            await _mf.StopAsync().ConfigureAwait(true);
            SetActive(_vlc!);
            _vlc!.AttachSurfaces(null, _vlcSurface);
            try
            {
                await _vlc.PrepareAsync(request, ct).ConfigureAwait(true);
                if (_vlc.State is not PlayerState.Error)
                    return;
            }
            catch
            {
                // fall through to MF
            }
        }

        // MF path (forced mediaFoundation, or auto DirectPlay, or VLC failed)
        var allowFallback = _preferredBackend == "auto" && _vlc is not null;

        SetActive(_mf);
        _mf.AttachSurfaces(_mfSurface, null);

        var tcs = new TaskCompletionSource<bool>();
        void OnErr(object? _, string msg) => tcs.TrySetResult(false);
        void OnState(object? _, PlayerState s)
        {
            if (s is PlayerState.Paused or PlayerState.Playing or PlayerState.Buffering)
                tcs.TrySetResult(true);
            if (s == PlayerState.Error)
                tcs.TrySetResult(false);
        }

        _mf.ErrorOccurred += OnErr;
        _mf.StateChanged += OnState;
        try
        {
            await _mf.PrepareAsync(request, ct).ConfigureAwait(true);
            var finished = await Task.WhenAny(tcs.Task, Task.Delay(12000, ct)).ConfigureAwait(true);
            var ok = finished == tcs.Task && await tcs.Task.ConfigureAwait(true);

            if (ok && _mf.State is not PlayerState.Error)
            {
                SetActive(_mf);
                return;
            }
        }
        catch
        {
            // fall through
        }
        finally
        {
            _mf.ErrorOccurred -= OnErr;
            _mf.StateChanged -= OnState;
        }

        if (!allowFallback || _vlc is null)
        {
            ErrorOccurred?.Invoke(this,
                _vlc is null
                    ? "Media Foundation failed and LibVLC is not available (native libs missing or USE_LIBVLC off)."
                    : "Media Foundation failed (LibVLC fallback disabled by settings).");
            return;
        }

        await _mf.StopAsync().ConfigureAwait(true);
        SetActive(_vlc);
        _vlc.AttachSurfaces(null, _vlcSurface);
        await _vlc.PrepareAsync(request, ct).ConfigureAwait(true);
    }

    public void Play() => _active.Play();
    public void Pause() => _active.Pause();
    public Task StopAsync() => _active.StopAsync();
    public Task SeekAsync(long positionMs, CancellationToken ct = default) => _active.SeekAsync(positionMs, ct);
    public Task SelectAudioTrackAsync(int streamId, int listIndex = -1, CancellationToken ct = default) =>
        _active.SelectAudioTrackAsync(streamId, listIndex, ct);
    public Task SelectSubtitleAsync(int? streamId, CancellationToken ct = default) =>
        _active.SelectSubtitleAsync(streamId, ct);

    public async ValueTask DisposeAsync()
    {
        await _mf.DisposeAsync();
        if (_vlc is not null) await _vlc.DisposeAsync();
    }

    private void SetActive(IPlayerEngine engine)
    {
        if (ReferenceEquals(_active, engine)) return;
        _active = engine;
        BackendChanged?.Invoke(this, engine.Backend);
    }

    private void Wire(IPlayerEngine engine)
    {
        engine.StateChanged += (_, s) =>
        {
            if (ReferenceEquals(_active, engine)) StateChanged?.Invoke(this, s);
        };
        engine.PositionChanged += (_, _) =>
        {
            if (ReferenceEquals(_active, engine)) PositionChanged?.Invoke(this, EventArgs.Empty);
        };
        engine.ErrorOccurred += (_, msg) =>
        {
            if (ReferenceEquals(_active, engine)) ErrorOccurred?.Invoke(this, msg);
        };
        engine.TracksChanged += (_, _) =>
        {
            if (ReferenceEquals(_active, engine)) TracksChanged?.Invoke(this, EventArgs.Empty);
        };
    }

    private static string Normalize(string? preferred) =>
        (preferred ?? "auto").Trim().ToLowerInvariant() switch
        {
            "mediafoundation" or "mf" => "mediafoundation",
            "libvlc" or "vlc" => "libvlc",
            _ => "auto"
        };
}
