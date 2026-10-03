using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;
using PlexWindows.Playback;
using LibVLCSharp.Platforms.Windows;
using PlexWindows.ViewModels;
using Windows.System;

namespace PlexWindows.Views;

public sealed partial class PlayerPage : Page
{
    public PlayerViewModel ViewModel { get; }
    private bool _dragSeeking;

    public PlayerPage()
    {
        ViewModel = App.Services.GetRequiredService<PlayerViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    private LibVLCSharp.Platforms.Windows.VideoView? _vlcView;

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        EnsureVlcView();
        // Dual surfaces: MF → MediaPlayerElement, LibVLC → VideoView
        ViewModel.Player.AttachSurfaces(MfElement, _vlcView);
        if (e.Parameter is PlaybackRequest req)
            _ = ViewModel.LoadAsync(req);
        Focus(FocusState.Programmatic);
    }

    private void EnsureVlcView()
    {
        if (_vlcView is not null) return;
        try
        {
            _vlcView = new LibVLCSharp.Platforms.Windows.VideoView
            {
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Stretch
            };
            _vlcView.Initialized += VlcView_Initialized;
            VlcHost.Child = _vlcView;
        }
        catch (Exception ex)
        {
            ViewModel.StatusMessage = "LibVLC VideoView unavailable: " + ex.Message;
        }
    }

    protected override async void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        await ViewModel.StopAsync();
    }


    private void VlcView_Initialized(object sender, InitializedEventArgs e)
    {
        if (ViewModel.Player is PlayerEngineRouter router)
            router.NotifyVlcViewInitialized(e.SwapChainOptions);
        else if (ViewModel.Player is LibVlcPlayerEngine vlc)
            vlc.OnVideoViewInitialized(e.SwapChainOptions);
    }

    private void PlayPause_Click(object sender, RoutedEventArgs e) => ViewModel.TogglePlayPause();
    private async void SkipBack_Click(object sender, RoutedEventArgs e) => await ViewModel.SkipAsync(-10);
    private async void SkipFwd_Click(object sender, RoutedEventArgs e) => await ViewModel.SkipAsync(10);
    private void Mute_Click(object sender, RoutedEventArgs e) => ViewModel.ToggleMute();

    private void Exit_Click(object sender, RoutedEventArgs e)
    {
        if (Frame.CanGoBack) Frame.GoBack();
    }

    private void Seek_ValueChanged(object sender, RangeBaseValueChangedEventArgs e)
    {
        if (_dragSeeking || sender is Slider { FocusState: not FocusState.Unfocused })
            _dragSeeking = true;
    }

    private async void Seek_PointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        if (sender is Slider slider)
        {
            await ViewModel.SeekAsync(slider.Value);
            _dragSeeking = false;
        }
    }

    private async void Audio_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        // Ignore programmatic refresh / mid-reload selection noise
        if (ViewModel.IsTrackListUpdating) return;
        if (e.AddedItems.Count == 0) return;
        if (e.AddedItems.FirstOrDefault() is not TrackInfo track) return;
        var index = sender is ComboBox cb ? cb.SelectedIndex : -1;
        await ViewModel.SelectAudioAsync(track, index);
    }

    private async void Subtitle_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (e.AddedItems.Count == 0) return;
        if (e.AddedItems.FirstOrDefault() is TrackInfo track)
            await ViewModel.SelectSubtitleAsync(track);
    }

    private void Page_PointerMoved(object sender, PointerRoutedEventArgs e) => ViewModel.BumpControls();

    private void Page_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        if (e.OriginalSource == MfElement || e.OriginalSource == VlcHost || e.OriginalSource == _vlcView)
            ViewModel.ToggleControlsVisible();
        else
            ViewModel.BumpControls();
    }

    private async void Page_KeyDown(object sender, KeyRoutedEventArgs e)
    {
        ViewModel.BumpControls();
        switch (e.Key)
        {
            case VirtualKey.Space:
            case (VirtualKey)179 /* VK_MEDIA_PLAY_PAUSE */:
                ViewModel.TogglePlayPause();
                e.Handled = true;
                break;
            case VirtualKey.Left:
            case VirtualKey.J:
                await ViewModel.SkipAsync(-10);
                e.Handled = true;
                break;
            case VirtualKey.Right:
            case VirtualKey.L:
                await ViewModel.SkipAsync(10);
                e.Handled = true;
                break;
            case VirtualKey.Up:
                ViewModel.Volume = Math.Clamp(ViewModel.Volume + 0.05, 0, 1);
                e.Handled = true;
                break;
            case VirtualKey.Down:
                ViewModel.Volume = Math.Clamp(ViewModel.Volume - 0.05, 0, 1);
                e.Handled = true;
                break;
            case VirtualKey.M:
                ViewModel.ToggleMute();
                e.Handled = true;
                break;
            case VirtualKey.Escape:
                if (Frame.CanGoBack) Frame.GoBack();
                e.Handled = true;
                break;
            case (VirtualKey)178 /* VK_MEDIA_STOP */:
                await ViewModel.StopAsync();
                e.Handled = true;
                break;
        }
    }
}
