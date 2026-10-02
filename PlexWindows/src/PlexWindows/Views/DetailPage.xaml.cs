using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using PlexWindows.Models;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class DetailPage : Page
{
    public DetailViewModel ViewModel { get; }

    public DetailPage()
    {
        ViewModel = App.Services.GetRequiredService<DetailViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is string ratingKey)
        {
            ViewModel.RatingKey = ratingKey;
            _ = ViewModel.LoadAsync();
        }
    }

    private async void Play_Click(object sender, RoutedEventArgs e)
    {
        var req = await ViewModel.BuildPlaybackRequestAsync();
        if (req is null) return;
        Frame.Navigate(typeof(PlayerPage), req);
    }

    private async void Favorite_Click(object sender, RoutedEventArgs e)
    {
        await ViewModel.ToggleFavoriteAsync();
    }

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        if (Frame.CanGoBack) Frame.GoBack();
    }

    private async void Child_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not FrameworkElement { Tag: PlexMetadata child }) return;

        if (child.Type is PlexMetadataType.Episode or PlexMetadataType.Track or PlexMetadataType.Movie)
        {
            var req = await ViewModel.BuildPlaybackRequestAsync(child);
            if (req is not null)
                Frame.Navigate(typeof(PlayerPage), req);
        }
        else
        {
            Frame.Navigate(typeof(DetailPage), child.RatingKey);
        }
    }
}
