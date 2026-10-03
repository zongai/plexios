using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Controls.Primitives;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Navigation;
using PlexWindows.Playback;
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

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        // Dual surfaces: MF → MediaPlayerElement, LibVLC → VideoView
        ViewModel.Player.AttachSurfaces(MfElement, VlcHost);
        if (e.Parameter is PlaybackRequest req)
            _ = ViewModel.LoadAsync(req);
        Focus(FocusState.Programmatic);
    }

    protected override async void OnNavigatedFrom(NavigationEventArgs e)
    {
        base.OnNavigatedFrom(e);
        await ViewModel.StopAsync();
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
        // Ignore programmatic refresh of ItemsSource/SelectedItem
        if (e.AddedItems.Count == 0) return;
        if (e.AddedItems.FirstOrDefault() is TrackInfo track)
            await ViewModel.SelectAudioAsync(track);
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
        if (e.OriginalSource == MfElement || e.OriginalSource == VlcHost)
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
