using Microsoft.Extensions.DependencyInjection;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using PlexWindows.Helpers;
using PlexWindows.ViewModels;

namespace PlexWindows.Views;

public sealed partial class CollectionsPage : Page
{
    public CollectionsViewModel ViewModel { get; }

    public CollectionsPage()
    {
        ViewModel = App.Services.GetRequiredService<CollectionsViewModel>();
        InitializeComponent();
        DataContext = ViewModel;
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        _ = ViewModel.LoadAsync();
    }

    private async void Collection_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: MediaCardItem card })
            await ViewModel.OpenCollectionAsync(card);
    }

    private void Child_Click(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement { Tag: MediaCardItem card })
            Frame.Navigate(typeof(DetailPage), card.RatingKey);
    }

    private void Back_Click(object sender, RoutedEventArgs e) => ViewModel.BackToList();
}
