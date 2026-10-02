using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PlexWindows.Models;
using PlexWindows.Plex.Api;
using PlexWindows.Playback;
using PlexWindows.Services;

namespace PlexWindows.ViewModels;

public partial class PlayerViewModel : ObservableObject
{
    private readonly IPlayerEngine _player;
    private readonly PlexApiClient _api;
    private readonly PlaybackDecisionEngine _decisionEngine;
    private readonly PlaybackUrlBuilder _urlBuilder;
    private readonly TimelineReporter _timeline;
    private readonly AppSettings _settings;
    private PlaybackPreferences _prefs = PlaybackPreferences.Default;
    private CancellationTokenSource? _controlsCts;
    private bool _seeking;

    [ObservableProperty] private string _title = "";
    [ObservableProperty] private string _subtitle = "";
    [ObservableProperty] private bool _isPlaying;
    [ObservableProperty] private string _playPauseLabel = "Play";
    [ObservableProperty] private double _positionSeconds;
    [ObservableProperty] private double _durationSeconds;
    [ObservableProperty] private string _positionText = "0:00";
    [ObservableProperty] private string _durationText = "0:00";
    [ObservableProperty] private string _statusMessage = "";
    [ObservableProperty] private string _decisionReason = "";
    [ObservableProperty] private string _modeLabel = "";
    [ObservableProperty] private bool _showControls = true;
    [ObservableProperty] private bool _isBuffering;
    [ObservableProperty] private double _volume = 1.0;
    [ObservableProperty] private bool _isMuted;
    [ObservableProperty] private string _muteLabel = "🔊";
    [ObservableProperty] private IReadOnlyList<TrackInfo> _audioTracks = Array.Empty<TrackInfo>();
    [ObservableProperty] private IReadOnlyList<TrackInfo> _subtitleTracks = Array.Empty<TrackInfo>();
    [ObservableProperty] private TrackInfo? _selectedAudio;
    [ObservableProperty] private TrackInfo? _selectedSubtitle;
    [ObservableProperty] private bool _hasAudioTracks;
    [ObservableProperty] private bool _hasSubtitleTracks;
    [ObservableProperty] private bool _showMfSurface = true;
    [ObservableProperty] private bool _showVlcSurface;
    [ObservableProperty] private string _backendLabel = "MediaFoundation";

    public PlaybackRequest? Request { get; private set; }
    public IPlayerEngine Player => _player;

    /// <summary>Synthetic "Off" subtitle entry for ComboBox.</summary>
    public TrackInfo SubtitleOff { get; } = new() { Id = -1, Title = "Off" };

    public PlayerViewModel(
        IPlayerEngine player,
        PlexApiClient api,
        PlaybackDecisionEngine decisionEngine,
        PlaybackUrlBuilder urlBuilder,
        TimelineReporter timeline,
        AppSettings settings)
    {
        _player = player;
        _api = api;
        _decisionEngine = decisionEngine;
        _urlBuilder = urlBuilder;
        _timeline = timeline;
        _settings = settings;
        ApplySettings();

        _player.StateChanged += OnStateChanged;
        _player.ErrorOccurred += (_, msg) => StatusMessage = msg;
        _player.PositionChanged += OnPositionChanged;
        _player.TracksChanged += OnTracksChanged;
        _player.BackendChanged += OnBackendChanged;
        ApplyBackend(_player.Backend);
    }

    private void ApplySettings()
    {
        _prefs = new PlaybackPreferences
        {
            AutoPlayNextEpisode = _settings.AutoPlayNextEpisode,
            MaxVideoBitrateKbps = Math.Max(1000, _settings.MaxRemoteBitrate / 1000)
        };
        if (_player is PlayerEngineRouter router)
            router.SetPreferredBackend(_settings.PlayerBackend);
    }

    private void OnBackendChanged(object? sender, PlayerBackendKind kind) => ApplyBackend(kind);

    private void ApplyBackend(PlayerBackendKind kind)
    {
        ShowMfSurface = kind == PlayerBackendKind.MediaFoundation;
        ShowVlcSurface = kind == PlayerBackendKind.LibVlc;
        BackendLabel = kind switch
        {
            PlayerBackendKind.LibVlc => "LibVLC",
            _ => "MediaFoundation"
        };
    }

    public async Task LoadAsync(PlaybackRequest request)
    {
        ApplySettings();
        Request = request;
        Title = request.Metadata.Title;
        var show = request.Metadata.GrandparentTitle;
        var season = request.Metadata.ParentTitle;
        Subtitle = show is not null
            ? $"{show} · {season}"
            : season ?? request.Decision.Mode.ToString();
        DecisionReason = request.Decision.Reason;
        ModeLabel = request.Decision.Mode switch
        {
            PlaybackMode.DirectPlay => "Direct Play",
            PlaybackMode.DirectStream => "Direct Stream",
            _ => "Transcode"
        };
        StatusMessage = "";
        Volume = _player.Volume;
        IsMuted = _player.IsMuted;

        try
        {
            await _player.PrepareAsync(request);
            DurationSeconds = Math.Max(_player.DurationMs, request.Metadata.Duration ?? 0) / 1000.0;
            PositionSeconds = request.StartPositionMs / 1000.0;
            UpdateTimeLabels();
            RefreshTracks();
            _player.Play();
            IsPlaying = true;
            PlayPauseLabel = "Pause";
            ScheduleControlsAutoHide();
            _ = ReportAsync("playing");
        }
        catch (Exception ex)
        {
            StatusMessage = ex.Message;
        }
    }

    [RelayCommand]
    public void TogglePlayPause()
    {
        if (IsPlaying)
        {
            _player.Pause();
            _ = ReportAsync("paused");
        }
        else
        {
            _player.Play();
            _ = ReportAsync("playing");
        }
        BumpControls();
    }

    [RelayCommand]
    public async Task SeekAsync(double seconds)
    {
        _seeking = true;
        try
        {
            await _player.SeekAsync((long)(seconds * 1000));
            PositionSeconds = seconds;
            UpdateTimeLabels();
            _ = ReportAsync(IsPlaying ? "playing" : "paused");
        }
        finally
        {
            _seeking = false;
        }
        BumpControls();
    }

    [RelayCommand]
    public async Task SkipAsync(int deltaSeconds)
    {
        var next = DurationSeconds > 0
            ? Math.Clamp(PositionSeconds + deltaSeconds, 0, DurationSeconds)
            : Math.Max(0, PositionSeconds + deltaSeconds);
        await SeekAsync(next);
    }

    [RelayCommand]
    public async Task StopAsync()
    {
        await _player.StopAsync();
        IsPlaying = false;
        PlayPauseLabel = "Play";
        _ = ReportAsync("stopped");
    }

    [RelayCommand]
    public void ToggleMute()
    {
        IsMuted = !IsMuted;
        _player.IsMuted = IsMuted;
        MuteLabel = IsMuted ? "🔇" : "🔊";
        BumpControls();
    }

    partial void OnIsMutedChanged(bool value)
    {
        MuteLabel = value ? "🔇" : "🔊";
    }

    partial void OnVolumeChanged(double value)
    {
        _player.Volume = value;
        if (value > 0 && IsMuted)
        {
            IsMuted = false;
            _player.IsMuted = false;
        }
    }

    public async Task SelectAudioAsync(TrackInfo? track)
    {
        if (track is null) return;
        SelectedAudio = track;
        await _player.SelectAudioTrackAsync(track.Id);
        BumpControls();
    }

    public async Task SelectSubtitleAsync(TrackInfo? track)
    {
        if (track is null || track.Id < 0)
        {
            SelectedSubtitle = SubtitleOff;
            await _player.SelectSubtitleAsync(null);
        }
        else
        {
            SelectedSubtitle = track;
            await _player.SelectSubtitleAsync(track.Id);
        }
        BumpControls();
    }

    public void BumpControls()
    {
        ShowControls = true;
        ScheduleControlsAutoHide();
    }

    public void ToggleControlsVisible()
    {
        ShowControls = !ShowControls;
        if (ShowControls) ScheduleControlsAutoHide();
    }

    private void OnStateChanged(object? sender, PlayerState state)
    {
        IsPlaying = state == PlayerState.Playing;
        IsBuffering = state == PlayerState.Buffering || state == PlayerState.Opening;
        PlayPauseLabel = IsPlaying ? "Pause" : "Play";

        if (state == PlayerState.Ended)
            _ = OnEndedAsync();
        else if (state == PlayerState.Buffering)
            _ = ReportAsync("buffering");
    }

    private void OnPositionChanged(object? sender, EventArgs e)
    {
        if (_seeking) return;
        PositionSeconds = _player.PositionMs / 1000.0;
        if (_player.DurationMs > 0)
            DurationSeconds = _player.DurationMs / 1000.0;
        UpdateTimeLabels();
        if (IsPlaying)
            _ = ReportAsync("playing");
    }

    private void OnTracksChanged(object? sender, EventArgs e) => RefreshTracks();

    private void RefreshTracks()
    {
        AudioTracks = _player.AudioTracks.ToList();
        var subs = _player.SubtitleTracks.ToList();
        // Prepend Off
        var withOff = new List<TrackInfo> { SubtitleOff };
        withOff.AddRange(subs);
        SubtitleTracks = withOff;

        HasAudioTracks = AudioTracks.Count > 0;
        HasSubtitleTracks = SubtitleTracks.Count > 1; // more than just Off

        SelectedAudio = AudioTracks.FirstOrDefault(t => t.IsSelected) ?? AudioTracks.FirstOrDefault();
        SelectedSubtitle = subs.FirstOrDefault(t => t.IsSelected) ?? SubtitleOff;
    }

    private void UpdateTimeLabels()
    {
        PositionText = FormatTime(PositionSeconds);
        DurationText = FormatTime(DurationSeconds);
    }

    private static string FormatTime(double seconds)
    {
        if (double.IsNaN(seconds) || seconds < 0) seconds = 0;
        var t = TimeSpan.FromSeconds(seconds);
        return t.TotalHours >= 1
            ? $"{(int)t.TotalHours}:{t.Minutes:D2}:{t.Seconds:D2}"
            : $"{t.Minutes}:{t.Seconds:D2}";
    }

    private void ScheduleControlsAutoHide()
    {
        _controlsCts?.Cancel();
        _controlsCts = new CancellationTokenSource();
        var ct = _controlsCts.Token;
        _ = Task.Run(async () =>
        {
            try
            {
                await Task.Delay(3500, ct);
                if (!ct.IsCancellationRequested && IsPlaying)
                    ShowControls = false;
            }
            catch (OperationCanceledException) { }
        }, ct);
    }

    private async Task ReportAsync(string state)
    {
        if (Request is null) return;
        await _timeline.ReportAsync(
            Request.Context,
            Request.Metadata.RatingKey,
            _player.PositionMs,
            _player.DurationMs > 0 ? _player.DurationMs : (Request.Metadata.Duration ?? 0),
            state);
    }

    private async Task OnEndedAsync()
    {
        _ = ReportAsync("stopped");
        if (!_prefs.AutoPlayNextEpisode || Request is null) return;
        if (Request.Metadata.Type != PlexMetadataType.Episode) return;

        try
        {
            StatusMessage = "Loading next episode…";
            var next = await NextEpisodeResolver.FindNextAsync(_api, Request.Context, Request.Metadata);
            if (next is null)
            {
                StatusMessage = "Playback finished.";
                return;
            }

            var decision = _decisionEngine.Decide(next, Request.Network);
            var url = _urlBuilder.Build(Request.Context, next, decision);
            var nextReq = new PlaybackRequest
            {
                Metadata = next,
                Context = Request.Context,
                Network = Request.Network,
                Decision = decision,
                MediaUrl = url,
                StartPositionMs = 0
            };
            await LoadAsync(nextReq);
        }
        catch (Exception ex)
        {
            StatusMessage = $"Next episode failed: {ex.Message}";
        }
    }
}
