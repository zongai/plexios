using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using PlexWindows.Helpers;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class PlaylistsPage : Page
{
    public PlaylistsViewModel ViewModel { get; }

    public PlaylistsPage()
    {
        ViewModel = App.Services.GetRequiredService<PlaylistsViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _ = ViewModel.LoadAsync();
    }

    private async void Playlist_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: MediaCardItem card })
            await ViewModel.OpenPlaylistAsync(card);
    }

    private void Item_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: MediaCardItem card })
            Frame.Navigate(typeof(DetailPage), card.RatingKey);
    }

    private void Back_Click(object sender, RoutedEventArgs e) => ViewModel.BackToList();
}
